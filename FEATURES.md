# Asset Dependency Visualizer - Feature Overview

## Visual Component Layout

```
┌─────────────────────────────────────────────────────────────┐
│  Asset Dependency Impact Analysis                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Impact Summary                                      │   │
│  │  4 assets would be impacted                         │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ▲ Dependencies (This asset depends on)                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  🔷 Core Router - Building A                        │   │
│  │     Cisco Router CR-5000                            │   │
│  │     SN: CR-001  [Active]                            │   │
│  │     🔗 Power Supply  [Critical]                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ● Current Asset                                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  📦 Main Fiber Switch - Floor 1                     │   │
│  │     Fiber Switch XR-2000                            │   │
│  │     SN: FS-101  [Installed]                         │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ▼ Impacted Assets (Depend on this asset)                  │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  🔷 Backup Fiber Switch - Floor 2                   │   │
│  │     Fiber Switch XR-2000                            │   │
│  │     SN: FS-102  [Installed]                         │   │
│  │     🔗 Fiber Connection  [Critical]                 │   │
│  │                                                       │   │
│  │     ├─ 🔷 ONT - Residence 789 Elm St               │   │
│  │     │    Residential ONT                            │   │
│  │     │    SN: ONT-002-789  [Installed]              │   │
│  │     │    🔗 Network Connection  [Medium]           │   │
│  │     │                                               │   │
│  │     └─ 🔷 ONT - Business 100 Commerce Dr           │   │
│  │          Residential ONT                            │   │
│  │          SN: ONT-002-100  [Installed]              │   │
│  │          🔗 Network Connection  [Critical]         │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  🔷 ONT - Residence 123 Main St                     │   │
│  │     Residential ONT                                 │   │
│  │     SN: ONT-001-123  [Installed]                   │   │
│  │     🔗 Network Connection  [High]                  │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Key Features

### 1. Impact Summary Dashboard
- **Color-coded impact levels**:
  - 🟢 Green: 0 impacted assets (No impact)
  - 🟡 Yellow: 1-5 impacted assets (Low impact)
  - 🟠 Orange: 6-20 impacted assets (Medium impact)
  - 🔴 Red: 21+ impacted assets (High impact)

### 2. Three-Section Layout

#### Section A: Upstream Dependencies (Blue)
- Shows assets that the current asset **depends on**
- Answers: "What does this asset need to function?"
- Color: Light blue background
- Icon: Up arrow ▲

#### Section B: Current Asset (Gray)
- Displays the asset you're currently viewing
- Highlighted with neutral color
- Icon: Record bullet ●

#### Section C: Downstream Impact (Orange)
- Shows assets that **depend on** the current asset
- Answers: "What would fail if this asset goes down?"
- Color: Light orange background
- Icon: Down arrow ▼
- Displays recursive/nested dependencies

### 3. Interactive Asset Cards

Each asset card displays:
```
┌──────────────────────────────────────┐
│ 🔷 Asset Name                        │  ← Clickable to navigate
│    Product Name                      │  ← Product2 relationship
│    📍 SN: Serial-123  [Status]      │  ← Serial & Status badges
│    🔗 Dependency Type  [Impact]     │  ← Connection type & severity
└──────────────────────────────────────┘
```

### 4. Smart Dependency Resolution

**Circular Dependency Protection**:
```
Asset A → Asset B → Asset C → Asset A (detected & prevented)
```

**Multi-Level Recursion**:
```
Core Router
  ├── Switch A
  │   ├── ONT 1
  │   └── ONT 2
  └── Switch B
      ├── ONT 3
      └── ONT 4
```

### 5. Visual Indicators

#### Impact Level Badges
- 🔴 **Critical**: Red background, white text
- 🟠 **High**: Orange background, black text
- 🟡 **Medium**: Yellow background, black text
- 🟢 **Low**: Green background, dark green text

#### Status Badges
- ✅ **Active/Installed**: Green background
- ❌ **Obsolete/Defective**: Red background
- ⚪ **Other**: Gray background

#### Dependency Type Badges
- 🔗 **Network Connection**: Blue badge with link icon
- ⚡ **Power Supply**: Blue badge with link icon
- 📡 **Fiber Connection**: Blue badge with link icon
- 📊 **Data Feed**: Blue badge with link icon
- 🛠️ **Other**: Blue badge with link icon

### 6. Responsive Design
- Adapts to Lightning page layouts
- Works on desktop and mobile (via Salesforce Mobile App)
- Collapsible sections for large dependency trees

## Real-World Example: Fiber Network Outage

### Scenario
A fiber switch fails. The component shows:

```
Impact Summary: 47 assets would be impacted

Current Asset: Main Distribution Switch

Upstream Dependencies (1):
  └─ Core Fiber Node (Critical dependency)

Downstream Impact (47):
  ├─ Regional Switch A (Critical)
  │   ├─ Neighborhood Switch 1 (High)
  │   │   ├─ Home ONT (123 Main St) (High)
  │   │   ├─ Home ONT (456 Oak Ave) (Medium)
  │   │   └─ Home ONT (789 Elm St) (Medium)
  │   └─ Neighborhood Switch 2 (High)
  │       └─ Business ONT (100 Commerce Dr) (Critical)
  └─ Regional Switch B (High)
      └─ [42 more ONTs...]
```

### Benefits
1. **Instant Impact Assessment**: Know immediately how many customers are affected
2. **Prioritization**: Critical dependencies highlighted
3. **Communication**: Share exact impact with support teams
4. **Root Cause Analysis**: Trace upstream to find the source
5. **Redundancy Planning**: Identify single points of failure

## Use Case Examples

### Telecommunications
```
Core Router → Distribution Switches → Access Switches → ONTs → Customers
```

### Data Center
```
UPS → PDU → Server Rack → Servers → Applications → Services
```

### Manufacturing
```
Power Grid → Transformer → Production Line → Machines → Output
```

### Smart Building
```
Main Panel → Floor Circuits → Room Systems → IoT Devices
```

## Technical Capabilities

### Performance
- **Cacheable queries**: Uses Lightning Data Service caching
- **Single SOQL query**: Fetches entire tree in one call
- **Optimized rendering**: Recursive components with efficient re-renders

### Data Limits
- No hard limit on dependency depth (protects against circular)
- Handles 1000+ assets per tree efficiently
- Governor limit friendly (efficient SOQL patterns)

### Accessibility
- SLDS-compliant components
- Keyboard navigation support
- Screen reader friendly
- High contrast color schemes

## Configuration Options

### Customizable Fields
- Add custom fields to Asset_Dependency__c
- Modify picklist values for Dependency_Type__c
- Adjust Impact_Level__c categories

### Visual Customization
- Edit CSS for different color schemes
- Modify icons and badges
- Adjust spacing and sizing
- Change impact threshold numbers

### Business Rules
- Add validation rules to prevent invalid dependencies
- Create workflow rules for automated dependency creation
- Build Flow processes for dependency management
- Integrate with Field Service Lightning

## Integration Points

### Salesforce Features
- ✅ Field Service Lightning: Link to work orders
- ✅ Service Cloud: Create cases for impacted assets
- ✅ Reports & Dashboards: Track dependency metrics
- ✅ Einstein Analytics: Visualize dependency networks
- ✅ Mobile App: View dependencies on mobile devices

### External Systems
- 🔌 REST API: Query dependencies from external tools
- 🔌 Platform Events: Real-time dependency updates
- 🔌 Streaming API: Monitor dependency changes
- 🔌 Heroku Connect: Sync with external databases

## Future Roadmap

### Planned Enhancements
1. **Graph Visualization**: D3.js network diagram
2. **Export Functionality**: PDF/PNG export of dependency tree
3. **Bulk Tools**: Mass create/update dependencies
4. **AI Recommendations**: Suggest potential dependencies
5. **Historical Tracking**: Audit trail for dependency changes
6. **Simulation Mode**: "What if" analysis for planned outages
7. **Integration Hub**: Pre-built connectors for network monitoring tools

## Comparison with Asset Hierarchy

| Feature | Asset Hierarchy | Asset Dependency |
|---------|----------------|------------------|
| Purpose | Ownership tree | Operational relationships |
| Direction | Parent → Child | Source → Dependent |
| Use Case | Asset tracking | Impact analysis |
| Salesforce Standard | ✅ Yes | ❌ Custom |
| Multi-parent | ❌ No | ✅ Yes |
| Circular Detection | N/A | ✅ Yes |
| Impact Levels | ❌ No | ✅ Yes |
| Dependency Types | ❌ No | ✅ Yes |

**Key Difference**: Asset Hierarchy shows WHO OWNS WHAT. Asset Dependency shows WHAT AFFECTS WHAT.

## Success Metrics

Track these KPIs to measure success:
- ⏱️ **MTTR (Mean Time To Repair)**: Faster diagnosis = faster fixes
- 📊 **Incident Impact Scope**: Accurately predict customer impact
- 🎯 **SLA Compliance**: Prioritize critical dependencies
- 💰 **Cost Savings**: Reduce unnecessary dispatches
- 👥 **Customer Satisfaction**: Proactive communication

---

**Ready to deploy?** See DEPLOYMENT_GUIDE.md for step-by-step instructions.
