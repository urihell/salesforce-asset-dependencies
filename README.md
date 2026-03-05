# Asset Dependency Visualizer for Salesforce

A Lightning Web Component that visualizes operational dependencies between assets in Salesforce. This component helps you understand the impact when an asset fails by showing which other assets depend on it.

## Features

- **Visual Dependency Tree**: See upstream (dependencies) and downstream (dependents) relationships
- **Impact Analysis**: Automatically calculates how many assets would be affected
- **Color-Coded Impact Levels**: Critical, High, Medium, Low with visual indicators
- **Interactive Navigation**: Click on any asset to navigate to its record page
- **Recursive Dependencies**: Handles multi-level dependency chains
- **Circular Dependency Protection**: Prevents infinite loops in dependency tracking

## Components

### Custom Object
- **Asset_Dependency__c**: Tracks operational relationships between assets
  - `Source_Asset__c`: The asset that others depend on (lookup to Asset)
  - `Dependent_Asset__c`: The asset that depends on the source (lookup to Asset)
  - `Dependency_Type__c`: Type of dependency (Network, Power, Fiber, etc.)
  - `Impact_Level__c`: Severity if source fails (Critical, High, Medium, Low)
  - `Is_Active__c`: Whether the dependency is currently active

### Custom Metadata Type
- **Product_Dependency_Rule__mdt**: Admin-configurable rules for auto-discovering product-based dependencies (no code changes needed to add new rules)
  - `Source_Keyword__c`: Keyword to match in the source product name
  - `Dependent_Keyword__c`: Keyword(s) for the dependent product (comma-separated)
  - `Dependency_Type__c`: e.g., "Fiber Connection", "Network Connection"
  - `Impact_Level__c`: e.g., "Critical", "High"
  - `Relationship_Category__c`: e.g., "Network", "Data"
  - `Dependency_Strength__c`: e.g., "Hard Stop", "Degraded Service"

  Ships with 3 default rules: Router→Switch, Switch→ONT/Modem, Server→Network

### Apex Classes
- **AssetDependencyController**: Queries and builds the dependency tree, auto-discovers dependencies using CMT rules
- **AssetGraphController**: Graph visualization with BFS traversal, critical path, and blast radius analysis
- **AssetDependencyControllerTest / AssetGraphControllerTest**: Comprehensive test coverage

### Lightning Web Components
- **assetDependencyVisualizer**: Main component for Asset record pages
- **assetNode**: Reusable component for displaying individual assets

## Installation

### Option A: Install the Released Package (Recommended)

Install the released unlocked package directly into your org — no CLI or source code required.

**Package Version ID:** `04tHo0000015xFsIAI`

1. **Click the install link:**
   [Install Asset Dependency Visualizer](https://login.salesforce.com/packaging/installPackage.apexp?p0=04tHo0000015xFsIAI)

2. **Or use the CLI:**
   ```bash
   sf package install --package 04tHo0000015xFsIAI --target-org <your-org-alias> --wait 10
   ```

### Option B: Deploy from Source

#### Prerequisites
- Salesforce CLI (sf CLI)
- A Salesforce org (Sandbox or Developer Edition recommended)
- Asset Management feature enabled

#### Deployment Steps

1. **Clone or download this repository**
   ```bash
   cd salesforce-asset-dependencies
   ```

2. **Authenticate with your Salesforce org**
   ```bash
   sf org login web --alias myorg
   ```

3. **Deploy the metadata**
   ```bash
   sf project deploy start --target-org myorg
   ```

4. **Assign permissions** (if needed)
   Navigate to Setup > Users > Permission Sets and assign appropriate permissions for Asset_Dependency__c

5. **Add component to Asset record page**
   - Navigate to any Asset record
   - Click Setup (gear icon) > Edit Page
   - Drag "Asset Dependency Visualizer" component onto the page
   - Save and activate the page

## Sample Data Setup

### Option 1: Using Anonymous Apex

Execute the following code in Developer Console (Debug > Open Execute Anonymous Window):

```apex
// Create Products
Product2 switchProduct = new Product2(Name = 'Fiber Switch XR-2000', IsActive = true);
Product2 routerProduct = new Product2(Name = 'Core Router CR-5000', IsActive = true);
Product2 ontProduct = new Product2(Name = 'Residential ONT', IsActive = true);
insert new List<Product2>{switchProduct, routerProduct, ontProduct};

// Create Assets
Asset coreRouter = new Asset(
    Name = 'Core Router - Building A',
    Product2Id = routerProduct.Id,
    SerialNumber = 'CR-001',
    Status = 'Installed'
);

Asset mainSwitch = new Asset(
    Name = 'Main Fiber Switch - Floor 1',
    Product2Id = switchProduct.Id,
    SerialNumber = 'FS-101',
    Status = 'Installed'
);

Asset backupSwitch = new Asset(
    Name = 'Backup Fiber Switch - Floor 2',
    Product2Id = switchProduct.Id,
    SerialNumber = 'FS-102',
    Status = 'Installed'
);

Asset ont1 = new Asset(
    Name = 'ONT - Residence 123 Main St',
    Product2Id = ontProduct.Id,
    SerialNumber = 'ONT-001-123',
    Status = 'Installed'
);

Asset ont2 = new Asset(
    Name = 'ONT - Residence 456 Oak Ave',
    Product2Id = ontProduct.Id,
    SerialNumber = 'ONT-001-456',
    Status = 'Installed'
);

Asset ont3 = new Asset(
    Name = 'ONT - Residence 789 Elm St',
    Product2Id = ontProduct.Id,
    SerialNumber = 'ONT-002-789',
    Status = 'Installed'
);

Asset ont4 = new Asset(
    Name = 'ONT - Business 100 Commerce Dr',
    Product2Id = ontProduct.Id,
    SerialNumber = 'ONT-002-100',
    Status = 'Installed'
);

insert new List<Asset>{coreRouter, mainSwitch, backupSwitch, ont1, ont2, ont3, ont4};

// Create Dependencies
List<Asset_Dependency__c> dependencies = new List<Asset_Dependency__c>{
    // Core Router feeds Main Switch
    new Asset_Dependency__c(
        Source_Asset__c = coreRouter.Id,
        Dependent_Asset__c = mainSwitch.Id,
        Dependency_Type__c = 'Fiber Connection',
        Impact_Level__c = 'Critical',
        Is_Active__c = true
    ),
    // Core Router feeds Backup Switch
    new Asset_Dependency__c(
        Source_Asset__c = coreRouter.Id,
        Dependent_Asset__c = backupSwitch.Id,
        Dependency_Type__c = 'Fiber Connection',
        Impact_Level__c = 'Critical',
        Is_Active__c = true
    ),
    // Main Switch feeds ONT1
    new Asset_Dependency__c(
        Source_Asset__c = mainSwitch.Id,
        Dependent_Asset__c = ont1.Id,
        Dependency_Type__c = 'Network Connection',
        Impact_Level__c = 'High',
        Is_Active__c = true
    ),
    // Main Switch feeds ONT2
    new Asset_Dependency__c(
        Source_Asset__c = mainSwitch.Id,
        Dependent_Asset__c = ont2.Id,
        Dependency_Type__c = 'Network Connection',
        Impact_Level__c = 'High',
        Is_Active__c = true
    ),
    // Backup Switch feeds ONT3
    new Asset_Dependency__c(
        Source_Asset__c = backupSwitch.Id,
        Dependent_Asset__c = ont3.Id,
        Dependency_Type__c = 'Network Connection',
        Impact_Level__c = 'Medium',
        Is_Active__c = true
    ),
    // Backup Switch feeds ONT4
    new Asset_Dependency__c(
        Source_Asset__c = backupSwitch.Id,
        Dependent_Asset__c = ont4.Id,
        Dependency_Type__c = 'Network Connection',
        Impact_Level__c = 'Critical',
        Is_Active__c = true
    )
};

insert dependencies;

System.debug('Sample data created successfully!');
System.debug('Core Router ID: ' + coreRouter.Id);
System.debug('Main Switch ID: ' + mainSwitch.Id);
```

### Option 2: Manual Setup

1. Create Products in Setup > Products
2. Create Assets related to those products
3. Create Asset Dependency records linking the assets

## Usage

1. Navigate to any Asset record that has dependencies configured
2. The component will automatically display:
   - **Impact Summary**: How many assets would be affected if this asset fails
   - **Dependencies (Upstream)**: Assets that this asset depends on (shown in blue)
   - **Current Asset**: The asset you're viewing
   - **Impacted Assets (Downstream)**: Assets that depend on this asset (shown in orange)

3. Click on any asset card to navigate to that asset's record page
4. The tree structure shows nested dependencies (e.g., if Switch A depends on Router B, and ONT C depends on Switch A, all levels are shown)

## Use Cases

### Telecommunications
- **Fiber Switch Failure**: See which ONTs and customer premises would lose service
- **Core Router Impact**: Understand how many downstream switches and devices are affected
- **Redundancy Planning**: Identify critical single points of failure

### Data Centers
- **Power Distribution**: Track which servers depend on specific PDUs
- **Network Topology**: Map switch-to-server dependencies
- **Cooling Systems**: Link CRAC units to dependent equipment

### Manufacturing
- **Production Lines**: Map machine dependencies and bottlenecks
- **Supply Chain**: Track component dependencies
- **Utility Infrastructure**: Power, water, compressed air dependencies

## Customization

### Adding New Dependency Types
Edit the `Dependency_Type__c` picklist in Setup:
1. Setup > Object Manager > Asset Dependency
2. Fields & Relationships > Dependency Type
3. Add your custom values

### Modifying Impact Levels
The component uses color coding based on impact levels:
- **Critical**: Red background
- **High**: Orange background
- **Medium**: Yellow background
- **Low**: Green background

To modify, edit `/force-app/main/default/lwc/assetNode/assetNode.css`

### Changing Visual Styling
The component uses SLDS (Salesforce Lightning Design System) and can be customized by editing:
- `/force-app/main/default/lwc/assetDependencyVisualizer/assetDependencyVisualizer.css`
- `/force-app/main/default/lwc/assetNode/assetNode.css`

## Testing

Run tests using:
```bash
sf apex run test --class-names AssetDependencyControllerTest --target-org myorg --result-format human
```

Expected test coverage: >90%

## Architecture

### Data Model
```
Asset (Standard Object)
  |
  +-- Asset_Dependency__c (Custom Object)
        |-- Source_Asset__c (Lookup to Asset)
        |-- Dependent_Asset__c (Lookup to Asset)
        |-- Dependency_Type__c (Picklist)
        |-- Impact_Level__c (Picklist)
        |-- Is_Active__c (Checkbox)
```

### Component Hierarchy
```
assetDependencyVisualizer (Parent LWC)
  |-- AssetDependencyController.getAssetDependencies() (Apex)
  |-- assetNode (Child LWC - Recursive)
        |-- assetNode (Recursive children)
```

## Troubleshooting

### Component not showing data
- Verify Asset_Dependency__c records exist with `Is_Active__c = true`
- Check that both Source_Asset__c and Dependent_Asset__c are populated
- Ensure user has Read access to Asset_Dependency__c

### "Error loading dependencies" message
- Open browser console to see detailed error
- Verify Apex class is deployed and accessible
- Check that the asset record exists and is accessible

### Circular dependency detected
- The component handles circular dependencies automatically
- If you see unexpected results, check your dependency data for loops

## API Version
This package uses Salesforce API version 62.0 (Winter '25)

## License
This project is provided as-is for educational and commercial use.

## Support
For issues or questions, please refer to the code comments or Salesforce documentation.

## Future Enhancements
- [x] Automated dependency discovery (hierarchy, shared account, product-based rules)
- [x] Bulk dependency creation tool (discovery preview modal with select/deselect and bulk attribute editing)
- [ ] Export dependency tree to PDF/Image
- [ ] Historical dependency tracking
- [ ] Integration with Service Cloud for incident management
- [ ] GraphQL-style dependency queries
