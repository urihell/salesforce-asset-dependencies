# Deployment Guide - Asset Dependency Visualizer

## Quick Start (5 Minutes)

### Step 1: Deploy to Salesforce
```bash
# Authenticate to your org
sf org login web --alias myorg

# Deploy all metadata
sf project deploy start --target-org myorg

# Verify deployment
sf project deploy report --target-org myorg
```

### Step 2: Add Component to Asset Page
1. Navigate to any Asset record in your org
2. Click the **Setup (gear) icon** > **Edit Page**
3. Find **Asset Dependency Visualizer** in the component list (left panel)
4. Drag it onto the page (recommended: right column or bottom)
5. Click **Save**
6. Click **Activate** and assign to the org default or specific profiles
7. Click **Back** to return to the record

### Step 3: Create Sample Data
Open Developer Console (Setup > Developer Console) and execute this script:

```apex
// Quick test with 3 assets
Product2 prod = new Product2(Name = 'Test Switch', IsActive = true);
insert prod;

Asset a1 = new Asset(Name = 'Main Switch', Product2Id = prod.Id, Status = 'Installed');
Asset a2 = new Asset(Name = 'Dependent Device 1', Product2Id = prod.Id, Status = 'Installed');
Asset a3 = new Asset(Name = 'Dependent Device 2', Product2Id = prod.Id, Status = 'Installed');
insert new List<Asset>{a1, a2, a3};

insert new List<Asset_Dependency__c>{
    new Asset_Dependency__c(
        Source_Asset__c = a1.Id,
        Dependent_Asset__c = a2.Id,
        Dependency_Type__c = 'Network Connection',
        Impact_Level__c = 'High',
        Is_Active__c = true
    ),
    new Asset_Dependency__c(
        Source_Asset__c = a1.Id,
        Dependent_Asset__c = a3.Id,
        Dependency_Type__c = 'Network Connection',
        Impact_Level__c = 'Medium',
        Is_Active__c = true
    )
};

System.debug('Main Switch ID: ' + a1.Id);
```

Copy the Asset ID from the debug log and navigate to that asset record to see the component in action!

## Production Deployment Checklist

### Pre-Deployment
- [ ] Review all code and metadata in sandbox
- [ ] Run all tests: `sf apex run test --test-level RunLocalTests --target-org myorg`
- [ ] Verify test coverage is >75% (current: >90%)
- [ ] Review field-level security requirements
- [ ] Document any custom picklist values added
- [ ] Create backup of production org (if possible)

### Deployment to Production
```bash
# 1. Authenticate to production
sf org login web --alias production

# 2. Validate deployment (doesn't deploy, just checks)
sf project deploy validate --target-org production --test-level RunLocalTests

# 3. If validation succeeds, deploy
sf project deploy start --target-org production --test-level RunLocalTests

# 4. Monitor deployment
sf project deploy report --target-org production
```

### Post-Deployment
- [ ] Verify all Apex classes deployed successfully
- [ ] Verify custom object and fields are accessible
- [ ] Add component to Asset page layouts
- [ ] Test with real asset data
- [ ] Create Asset_Dependency__c records for real assets
- [ ] Document the process for end users
- [ ] Train users on how to create dependencies
- [ ] Set up field-level security (if needed)

## Security & Permissions

### Object Permissions Required
Users need the following permissions on **Asset_Dependency__c**:
- Read (required)
- Create (optional - for creating dependencies)
- Edit (optional - for managing dependencies)
- Delete (optional - for cleanup)

### Grant Access via Permission Set
```bash
# Create a permission set (optional)
sf org create permset --name Asset_Dependency_Access --label "Asset Dependency Access" --target-org myorg
```

Or manually:
1. Setup > Permission Sets > New
2. Label: "Asset Dependency Access"
3. Object Settings > Asset Dependency
4. Enable Read, Create, Edit
5. Save
6. Assign to users

### Field-Level Security
By default, all fields are visible to users with object access. To restrict:
1. Setup > Object Manager > Asset Dependency
2. Fields & Relationships > [Field Name]
3. Set Field-Level Security per profile

## Troubleshooting Deployment

### Error: "Unknown custom object"
**Solution**: Deploy in order:
```bash
sf project deploy start --metadata-dir force-app/main/default/objects --target-org myorg
sf project deploy start --metadata-dir force-app/main/default/classes --target-org myorg
sf project deploy start --metadata-dir force-app/main/default/lwc --target-org myorg
```

### Error: "Insufficient privileges"
**Solution**: Ensure:
- You have "Modify All Data" or object-level permissions
- Custom object is deployed before fields
- API version compatibility (this package uses v62.0)

### Error: "Component not appearing on page"
**Solution**:
1. Verify deployment: Setup > Lightning Components (verify both components exist)
2. Clear browser cache
3. Check component visibility: Edit page > ensure component is present
4. Verify object permissions

### Test Failures
**Solution**:
```bash
# View detailed test results
sf apex get test --test-run-id [ID] --target-org myorg

# Run specific test class
sf apex run test --class-names AssetDependencyControllerTest --target-org myorg --detailed-coverage
```

## Rollback Procedure

If you need to remove the package:

```bash
# 1. Remove component from all Asset page layouts manually

# 2. Delete metadata
sf project delete source --metadata "LightningComponentBundle:assetDependencyVisualizer" --target-org myorg
sf project delete source --metadata "LightningComponentBundle:assetNode" --target-org myorg
sf project delete source --metadata "ApexClass:AssetDependencyController" --target-org myorg
sf project delete source --metadata "ApexClass:AssetDependencyControllerTest" --target-org myorg

# 3. Delete custom object (WARNING: This deletes all data)
# Go to Setup > Object Manager > Asset Dependency > Delete
```

**Note**: Deleting custom objects cannot be done via CLI if they contain data. You must delete all records first.

## Data Migration

### Exporting Dependencies
```bash
sf data query --query "SELECT Id, Source_Asset__c, Dependent_Asset__c, Dependency_Type__c, Impact_Level__c FROM Asset_Dependency__c" --result-format csv --target-org myorg > dependencies.csv
```

### Importing Dependencies
```bash
sf data import tree --plan data-import-plan.json --target-org myorg
```

### Bulk Load via Data Loader
1. Download Salesforce Data Loader
2. Export Assets (to map IDs)
3. Create CSV with columns: Source_Asset__c, Dependent_Asset__c, Dependency_Type__c, Impact_Level__c, Is_Active__c
4. Use Data Loader to insert Asset_Dependency__c records

## Performance Considerations

### Large Deployments (1000+ Assets)
- The component uses `@wire cacheable=true` for performance
- Dependency queries are optimized to fetch all levels in one query
- Consider adding indexes on lookup fields if query performance degrades

### Monitoring
```bash
# Check Apex performance
sf apex log tail --color --target-org myorg
```

### Limits
- Maximum dependency depth: Unlimited (protected by circular dependency detection)
- Maximum assets per query: ~50,000 (Salesforce governor limits)
- LWC cache expiration: Automatic per Salesforce LDS cache policy

## CI/CD Integration

### GitHub Actions Example
```yaml
name: Deploy to Salesforce
on:
  push:
    branches: [ main ]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: forcedotcom/cli-action@v1
      - run: sf org login sfdx-url --sfdx-url-file ${{ secrets.SFDX_AUTH_URL }}
      - run: sf project deploy start --test-level RunLocalTests
```

## Support & Contact
For deployment issues:
1. Check Salesforce Setup > Deployment Status
2. Review debug logs: Setup > Debug Logs
3. Check browser console for LWC errors
4. Verify API version compatibility

---
Last Updated: 2026-03-03
Package Version: 0.1.0
API Version: 62.0
