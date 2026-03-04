# Complete Asset Relationship Graph - Implementation Guide

## Overview
Transform the Asset Dependency Visualizer into a comprehensive dependency map + hierarchy explorer + risk lens system that provides a truly complete picture of asset relationships.

## Phase 1: Enhanced Data Model ✅ (Current Phase)

### New Custom Fields on Asset_Dependency__c
1. **Relationship_Category__c** (Picklist)
   - Values: Power, Network, Cooling, Data, Structural, Safety, Contract, Maintenance
   - Purpose: Color-code edges by category

2. **Dependency_Strength__c** (Picklist)
   - Values: Hard Stop, Degraded Service, Soft Dependency
   - Purpose: Control edge thickness (thick = hard stop, thin = soft)

3. **Relationship_Style__c** (Picklist)
   - Values: Physical, Logical, Inferred
   - Purpose: Edge line style (solid, dashed, dotted)

### Enhanced Asset Fields (To Add)
- `Health_Score__c` (Number): 0-100 health indicator
- `Criticality_Level__c` (Picklist): Critical, High, Medium, Low
- `SLA_Tier__c` (Text): Service level tier
- `Last_Telemetry__c` (DateTime): Last health check
- `Open_Work_Orders__c` (Number): Count of open WOs
- `Open_Cases__c` (Number): Count of open cases
- `Active_Alerts__c` (Number): Count of active alerts

## Phase 2: Core Graph Visualization

### Component Structure
```
assetRelationshipGraph (Main Container)
├── graphCanvas (D3.js-style SVG rendering)
├── graphToolbar (Search, filters, lenses)
├── graphLegend (Color/style key)
├── graphMiniMap (Overview navigator)
├── graphDetailsPanel (Selected node/edge info)
└── graphRelationshipTable (List view of relationships)
```

### Node Rendering
```javascript
Node Structure:
{
  id: assetId,
  type: 'facility|rack|device|circuit|vehicle|hvac',
  name: assetName,
  status: 'InService|Degraded|Down|Retired',
  health: healthScore,
  owner: ownerName,
  site: siteName,
  criticality: 'Critical|High|Medium|Low',
  signals: {
    openWOs: count,
    openCases: count,
    activeAlerts: count
  },
  badges: {
    slaTier: tier,
    warranty: status,
    compliance: status,
    safety: status
  },
  position: { x, y },
  size: calculated based on importance
}
```

### Edge Rendering
```javascript
Edge Structure:
{
  id: dependencyId,
  source: sourceAssetId,
  target: targetAssetId,
  category: 'Power|Network|Cooling|...',
  strength: 'HardStop|DegradedService|Soft',
  style: 'Physical|Logical|Inferred',
  label: 'Powered by|Connected to|...',
  impactLevel: 'Critical|High|Medium|Low'
}

Visual Encoding:
- Arrow: Always points from upstream → downstream
- Color: Based on category (Power=red, Network=blue, etc.)
- Thickness: Based on strength (5px=hard, 3px=degraded, 1px=soft)
- Style: Based on relationship (solid, dashed, dotted)
```

### Layout Algorithm
**Cross Layout**:
```
                [Parent Container]
                        |
[Upstream] ← [Focus Asset] → [Downstream]
                        |
                   [Children]
```

**Implementation**:
- Force-directed layout with custom forces
- Layered approach for clear hierarchy
- Collision detection to prevent overlap
- Edge bundling for dense connections

## Phase 3: Advanced Interactions

### Focus + Expansion Pattern
```javascript
Expansion Controls:
- Click node: Re-center focus
- Expand upstream: 1 hop, 2 hops, All
- Expand downstream: 1 hop, 2 hops, All
- Expand containment: Show parents/children
- Collapse: Hide sub-branches

Progressive Disclosure:
- Default: 1 hop each direction
- "Show More" button on nodes
- Lazy load additional relationships
```

### Filter System
```javascript
Filters:
1. Relationship Type
   - Power, Network, Cooling, Data, etc.
   - Multi-select with AND/OR logic

2. Asset Type
   - Facility, Device, Circuit, etc.
   - Supports wildcards

3. Status Filter
   - Show only: Impacted, Down, With Open WOs
   - Real-time updates

4. Time Lens
   - Alerts: Last 24h, 7d, 30d
   - Changes: Recent, Historical

5. Criticality Filter
   - Critical only, High+, All
```

### Lens System
```javascript
Normal Lens (Default):
- Show all relationships in scope
- Standard color coding

Critical Path Lens:
- Highlight minimum spanning tree
- Show shortest path from sources
- Dim non-critical edges
- Calculate using Dijkstra's algorithm

Blast Radius Lens:
- Red highlight for directly impacted (1 hop)
- Orange for indirect impact (2+ hops)
- Calculate recursively downstream
- Show impact count per node

Risk Lens:
- Heat map based on:
  * Criticality score
  * Open work count
  * Health score
  * Dependency count
- Color gradient: green→yellow→red
```

## Phase 4: Search & Navigation

### Search Implementation
```javascript
Search Features:
- Autocomplete asset name
- Search by serial number
- Search by location
- Search by type
- Jump to asset and focus

Breadcrumb Navigation:
Site > Building > Floor > Room > Rack > Device
- Click any level to jump
- Show containment hierarchy
- Update on focus change
```

### Mini-Map
```javascript
Mini-Map Features:
- 200x150px overview in corner
- Shows entire graph with viewport
- Drag viewport to pan
- Click to jump
- Auto-hide when small graph
```

## Phase 5: Details Panel & Tables

### Details Panel (Right Side)
```javascript
Tabs:
1. Overview
   - Asset details
   - Status & health
   - Key metrics
   - Quick stats

2. Relationships
   - Sortable table
   - All connections
   - Filter by type
   - Export CSV

3. Open Work
   - Work orders
   - Cases
   - Inspections
   - Create WO button

4. Health & Telemetry
   - Health history chart
   - Last readings
   - Alerts timeline

5. Notes & Docs
   - Attachments
   - Notes
   - Related docs
```

### Relationship Table View
```javascript
Columns:
- Related Asset
- Relationship Type
- Direction (Upstream/Downstream)
- Category
- Strength
- Impact Level
- Status
- Actions (View, Edit, Delete)

Features:
- Sort by any column
- Filter in-table
- Export visible rows
- Inline edit
- Bulk actions
```

## Phase 6: Visual Clarity Features

### Clustering
```javascript
Cluster Types:
1. Container-based
   - Collapse by rack
   - Collapse by room
   - Collapse by building

2. Pattern-based
   - Group identical sensors
   - Group redundant pairs
   - "12 identical ONTs" → cluster node

3. Edge Bundling
   - Bundle multiple edges between clusters
   - Show count on hover
   - Expand on click
```

### Zoom Levels
```javascript
Zoom Behaviors:
Zoomed Out (<50%)
 - Show clusters only
 - Critical edges only
 - No labels
 - Simple icons

Medium (50-150%)
 - Individual assets
 - All edges
 - Node names only
 - Category colors

Zoomed In (>150%)
 - Full details
 - Edge labels
 - Badges visible
 - Port/interface level
```

### Overlap Prevention
```javascript
Layout Algorithm:
- Force-directed with constraints
- Minimum node spacing
- Edge routing around nodes
- Quadtree for collision detection
- "Straighten" mode for trees
```

## Phase 7: Edge Cases & Error Handling

### Circular Dependencies
```javascript
Detection:
- DFS cycle detection
- Mark cycles with warning icon
- Special edge style (wavy)
- Show cycle path on hover

Visualization:
- Arc edges back to avoid confusion
- Highlight cycle participants
- Provide "Break cycle" action
```

### Many-to-Many
```javascript
Handling:
- Edge bundling threshold (>5 edges)
- Show count badge
- Expand on hover
- Popover with full list
```

### Missing Data
```javascript
Ghost Nodes:
- Dashed outline
- "Unknown" label
- Different icon
- Action: "Define Relationship"
- Visible in graph to show gaps
```

### Multiple Relationships (Same Assets)
```javascript
Edge Stacking:
- Offset parallel edges
- Stack badges
- Popover on click with all types
- Table view shows all rows
```

## Implementation Checklist

### Data Model
- [x] Add Relationship_Category__c field
- [x] Add Dependency_Strength__c field
- [x] Add Relationship_Style__c field
- [ ] Add Asset health/criticality fields
- [ ] Add Asset signals fields
- [ ] Migrate existing data with defaults

### Apex Controller
- [ ] Enhance getAssetDependencies for graph data
- [ ] Add getGraphData method (nodes + edges)
- [ ] Add expandNode method (lazy load)
- [ ] Add searchAssets with autocomplete
- [ ] Add getCriticalPath method
- [ ] Add getBlastRadius method
- [ ] Add getContainmentHierarchy method

### LWC Components
- [ ] Create assetRelationshipGraph component
- [ ] Create graphCanvas with SVG rendering
- [ ] Create graphNode component
- [ ] Create graphEdge component
- [ ] Create graphToolbar component
- [ ] Create graphLegend component
- [ ] Create graphMiniMap component
- [ ] Create graphDetailsPanel component
- [ ] Create graphRelationshipTable component

### Visualization Library
- [ ] Integrate D3.js or similar for graph layout
- [ ] Implement force-directed layout
- [ ] Implement edge routing
- [ ] Implement zoom/pan
- [ ] Implement node dragging
- [ ] Add animations/transitions

### Features
- [ ] Focus/expansion pattern
- [ ] Multi-hop expansion
- [ ] Filter system
- [ ] Lens system (Normal, Critical Path, Blast Radius)
- [ ] Search with autocomplete
- [ ] Breadcrumb navigation
- [ ] Mini-map
- [ ] Details panel with tabs
- [ ] Relationship table
- [ ] Export capabilities

### Visual Clarity
- [ ] Clustering algorithms
- [ ] Zoom-level behaviors
- [ ] Overlap prevention
- [ ] Edge bundling
- [ ] Responsive design

### Edge Cases
- [ ] Cycle detection & visualization
- [ ] Many-to-many handling
- [ ] Ghost nodes for missing data
- [ ] Multiple relationship types
- [ ] Performance optimization for >1000 nodes

## Performance Considerations

### Large Graphs (>500 nodes)
- Implement virtualization (only render visible)
- Use WebGL for rendering if available
- Lazy load relationships
- Cluster aggressively
- Limit initial load to 2 hops

### Real-time Updates
- WebSocket or Platform Events for live updates
- Incremental graph updates
- Avoid full re-render
- Update only affected nodes/edges

### Browser Compatibility
- Test on Chrome, Firefox, Safari, Edge
- Mobile browser support
- Fallback for no SVG support
- Accessibility (ARIA labels, keyboard nav)

## Deployment Strategy

### Phase 1 (Week 1)
- Deploy enhanced data model
- Migrate existing dependencies
- Update documentation

### Phase 2 (Weeks 2-3)
- Core graph visualization
- Basic node/edge rendering
- Focus/expansion pattern

### Phase 3 (Week 4)
- Filter and lens system
- Search and navigation
- Mini-map

### Phase 4 (Week 5)
- Details panel
- Relationship table
- Export features

### Phase 5 (Week 6)
- Clustering and zoom
- Edge case handling
- Performance optimization

### Phase 6 (Week 7)
- Testing and bug fixes
- User training
- Documentation

## Success Metrics

### User Adoption
- 80%+ of asset managers use graph view
- Average session time >5 minutes
- Repeat usage rate >70%

### Functionality
- Can answer all 8 core questions without leaving graph
- <2 seconds to render graphs up to 100 nodes
- <5 seconds for graphs up to 500 nodes

### Data Quality
- <5% missing relationships
- 0 circular dependency warnings
- 95%+ of dependencies have category/strength

## Next Steps
1. Review and approve data model changes
2. Deploy Phase 1 (enhanced fields)
3. Begin Phase 2 implementation
4. Set up development environment with D3.js
5. Create wireframes for graph layouts
6. Plan user testing sessions

---
**Status**: Phase 1 Ready for Deployment
**Last Updated**: 2026-03-03
**Owner**: Development Team
