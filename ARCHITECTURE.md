# Architecture Overview

## Component Structure

```
Asset Dependency Visualizer
│
├── Custom Objects
│   └── Asset_Dependency__c
│       ├── Source_Asset__c (Lookup → Asset)
│       ├── Dependent_Asset__c (Lookup → Asset)
│       ├── Dependency_Type__c (Picklist)
│       ├── Impact_Level__c (Picklist)
│       └── Is_Active__c (Checkbox)
│
├── Apex Classes
│   ├── AssetDependencyController.cls
│   │   ├── getAssetDependencies() - Main query method
│   │   ├── buildDependencyTree() - Recursive tree builder
│   │   └── buildAssetNode() - Node constructor
│   └── AssetDependencyControllerTest.cls
│
└── Lightning Web Components
    ├── assetDependencyVisualizer (Parent)
    │   ├── assetDependencyVisualizer.js
    │   ├── assetDependencyVisualizer.html
    │   ├── assetDependencyVisualizer.css
    │   └── assetDependencyVisualizer.js-meta.xml
    │
    └── assetNode (Child - Recursive)
        ├── assetNode.js
        ├── assetNode.html
        ├── assetNode.css
        └── assetNode.js-meta.xml
```

## Data Flow

```
User Views Asset Record
        ↓
Lightning Page loads assetDependencyVisualizer
        ↓
@wire calls AssetDependencyController.getAssetDependencies(recordId)
        ↓
Apex queries Asset_Dependency__c (both directions)
        ↓
Builds upstream tree (dependencies)
        ↓
Builds downstream tree (dependents)
        ↓
Returns AssetDependencyWrapper to LWC
        ↓
LWC renders assetNode components recursively
        ↓
User sees visual dependency tree
```

## Key Design Decisions

### 1. Bidirectional Relationships
- Single object with Source/Dependent lookups
- More flexible than master-detail
- Allows many-to-many relationships

### 2. Recursive Component Pattern
- assetNode calls itself for children
- Clean separation of concerns
- Easy to maintain and extend

### 3. Single Query Strategy
- Fetch all dependencies in one SOQL
- Process in memory (Apex)
- Reduces API calls and governor limits

### 4. Circular Dependency Protection
- Track processed asset IDs
- Skip already-visited nodes
- Prevents infinite loops
