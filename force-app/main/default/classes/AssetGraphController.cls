public with sharing class AssetGraphController {

    /**
     * Get complete graph data for visualization
     */
    @AuraEnabled(cacheable=true)
    public static GraphData getGraphData(Id focusAssetId, Integer maxHops) {
        try {
            GraphData graphData = new GraphData();
            graphData.focusAssetId = focusAssetId;

            Integer hops = (maxHops == null || maxHops < 1) ? 1 : Math.min(maxHops, 10);

            // BFS traversal outward from focusAssetId for the requested number of hops
            Set<Id> visitedAssetIds = new Set<Id>{focusAssetId};
            Set<Id> frontier = new Set<Id>{focusAssetId};
            List<Asset_Dependency__c> allDeps = new List<Asset_Dependency__c>();
            Set<Id> collectedDepIds = new Set<Id>();

            for (Integer hop = 0; hop < hops && !frontier.isEmpty(); hop++) {
                List<Asset_Dependency__c> hopDeps = [
                    SELECT Id, Source_Asset__c, Dependent_Asset__c,
                           Dependency_Type__c, Impact_Level__c, Is_Active__c,
                           Relationship_Category__c, Dependency_Strength__c, Relationship_Style__c,
                           Source_Asset__r.Name, Source_Asset__r.Status, Source_Asset__r.Product2.Name,
                           Dependent_Asset__r.Name, Dependent_Asset__r.Status, Dependent_Asset__r.Product2.Name
                    FROM Asset_Dependency__c
                    WHERE (Is_Active__c = true OR Is_Active__c = null)
                    AND (Source_Asset__c IN :frontier OR Dependent_Asset__c IN :frontier)
                ];

                Set<Id> nextFrontier = new Set<Id>();
                for (Asset_Dependency__c dep : hopDeps) {
                    if (!collectedDepIds.contains(dep.Id)) {
                        allDeps.add(dep);
                        collectedDepIds.add(dep.Id);
                    }
                    if (!visitedAssetIds.contains(dep.Source_Asset__c)) {
                        visitedAssetIds.add(dep.Source_Asset__c);
                        nextFrontier.add(dep.Source_Asset__c);
                    }
                    if (!visitedAssetIds.contains(dep.Dependent_Asset__c)) {
                        visitedAssetIds.add(dep.Dependent_Asset__c);
                        nextFrontier.add(dep.Dependent_Asset__c);
                    }
                }
                frontier = nextFrontier;
            }

            // Bulk-fetch asset details and signals
            Map<Id, Asset> assetMap = getAssetDetailsMap(visitedAssetIds);
            Map<Id, AssetSignals> signalsMap = getBulkAssetSignals(visitedAssetIds);

            // Build nodes
            for (Id assetId : visitedAssetIds) {
                Asset asset = assetMap.get(assetId);
                if (asset != null) {
                    graphData.nodes.add(buildGraphNode(asset, assetId == focusAssetId, signalsMap.get(assetId)));
                }
            }

            // Build edges
            for (Asset_Dependency__c dep : allDeps) {
                graphData.edges.add(buildGraphEdge(dep));
            }

            return graphData;

        } catch (Exception e) {
            throw new AuraHandledException('Error getting graph data: ' + e.getMessage());
        }
    }

    /**
     * Bulk-fetch asset details for a set of IDs (replaces single-record getAssetDetails)
     * @param assetIds Set of Asset IDs to query
     * @return Map of Asset ID to Asset record
     */
    private static Map<Id, Asset> getAssetDetailsMap(Set<Id> assetIds) {
        return new Map<Id, Asset>([
            SELECT Id, Name, Status, SerialNumber, Product2.Name, Product2Id,
                   AccountId, Account.Name, ContactId, Contact.Name,
                   ParentId, Parent.Name, RootAssetId
            FROM Asset
            WHERE Id IN :assetIds
        ]);
    }

    /**
     * Bulk-fetch signals (open work orders and cases) for a set of asset IDs.
     * Uses aggregate queries instead of per-record SOQL.
     * @param assetIds Set of Asset IDs to get signals for
     * @return Map of Asset ID to AssetSignals
     */
    private static Map<Id, AssetSignals> getBulkAssetSignals(Set<Id> assetIds) {
        Map<Id, AssetSignals> signalsMap = new Map<Id, AssetSignals>();
        for (Id assetId : assetIds) {
            signalsMap.put(assetId, new AssetSignals());
        }

        try {
            for (AggregateResult ar : [
                SELECT AssetId, COUNT(Id) cnt
                FROM WorkOrder
                WHERE AssetId IN :assetIds
                AND Status != 'Closed'
                AND Status != 'Canceled'
                GROUP BY AssetId
            ]) {
                Id assetId = (Id) ar.get('AssetId');
                if (signalsMap.containsKey(assetId)) {
                    signalsMap.get(assetId).openWorkOrders = (Integer) ar.get('cnt');
                }
            }
        } catch (Exception e) {
            // WorkOrder object may not be enabled
        }

        try {
            for (AggregateResult ar : [
                SELECT AssetId, COUNT(Id) cnt
                FROM Case
                WHERE AssetId IN :assetIds
                AND IsClosed = false
                GROUP BY AssetId
            ]) {
                Id assetId = (Id) ar.get('AssetId');
                if (signalsMap.containsKey(assetId)) {
                    signalsMap.get(assetId).openCases = (Integer) ar.get('cnt');
                }
            }
        } catch (Exception e) {
            // Case query failed - signals default to 0
        }

        try {
            String alertQuery = 'SELECT Id, Name, EffectiveDate, ValidUntilDate, WhatId '
                + 'FROM RecordAlert WHERE WhatId IN :assetIds ORDER BY EffectiveDate DESC';
            for (SObject ra : Database.query(alertQuery)) {
                Id whatId = (Id) ra.get('WhatId');
                if (signalsMap.containsKey(whatId)) {
                    AssetSignals sig = signalsMap.get(whatId);
                    sig.activeAlerts++;
                    sig.alertRecords.add(new AlertRecord(ra));
                }
            }
        } catch (Exception e) {
            // RecordAlert query failed - signals default to 0
        }

        return signalsMap;
    }

    /**
     * Build graph node from asset with pre-fetched signals
     * @param asset The Asset record
     * @param isFocus Whether this is the focus node
     * @param signals Pre-fetched signals (null-safe)
     * @return GraphNode for the asset
     */
    private static GraphNode buildGraphNode(Asset asset, Boolean isFocus, AssetSignals signals) {
        GraphNode node = new GraphNode();
        node.id = asset.Id;
        node.name = asset.Name;
        node.assetType = asset.Product2?.Name ?? 'Asset';
        node.status = asset.Status;
        node.serialNumber = asset.SerialNumber;
        node.isFocus = isFocus;
        node.nodeType = determineNodeType(asset);
        node.signals = signals ?? new AssetSignals();
        node.owner = asset.Contact?.Name;
        node.site = asset.Account?.Name;
        node.parentId = asset.ParentId;
        node.parentName = asset.Parent?.Name;
        return node;
    }

    /**
     * Determine node type for icon selection
     */
    private static String determineNodeType(Asset asset) {
        String productName = asset.Product2?.Name?.toLowerCase();
        if (productName == null) return 'device';

        if (productName.contains('switch') || productName.contains('router')) return 'network';
        if (productName.contains('ont') || productName.contains('modem')) return 'device';
        if (productName.contains('server')) return 'server';
        if (productName.contains('rack')) return 'rack';
        if (productName.contains('building') || productName.contains('facility')) return 'facility';
        if (productName.contains('vehicle')) return 'vehicle';
        if (productName.contains('hvac') || productName.contains('cooling')) return 'hvac';

        return 'device';
    }


    /**
     * Build graph edge from dependency
     */
    private static GraphEdge buildGraphEdge(Asset_Dependency__c dep) {
        GraphEdge edge = new GraphEdge();
        edge.id = dep.Id;
        edge.source = dep.Source_Asset__c;
        edge.target = dep.Dependent_Asset__c;
        edge.dependencyType = dep.Dependency_Type__c;
        edge.impactLevel = dep.Impact_Level__c;
        edge.category = dep.Relationship_Category__c;
        edge.strength = dep.Dependency_Strength__c;
        edge.style = dep.Relationship_Style__c;

        // Build edge label
        edge.label = buildEdgeLabel(dep.Dependency_Type__c, dep.Relationship_Category__c);

        return edge;
    }

    /**
     * Build human-readable edge label
     */
    private static String buildEdgeLabel(String depType, String category) {
        if (String.isNotBlank(depType)) {
            return depType;
        }
        if (String.isNotBlank(category)) {
            return category + ' Connection';
        }
        return 'Depends on';
    }

    /**
     * Expand node to get additional relationships
     */
    @AuraEnabled(cacheable=true)
    public static GraphData expandNode(Id nodeId, Id focusAssetId, Integer hops, String direction) {
        try {
            GraphData graphData = new GraphData();
            graphData.focusAssetId = focusAssetId;

            Set<Id> processedAssets = new Set<Id>();
            Set<Id> currentLevel = new Set<Id>{nodeId};

            // Collect all deps across hops first
            List<Asset_Dependency__c> allCollectedDeps = new List<Asset_Dependency__c>();

            for (Integer i = 0; i < hops; i++) {
                Set<Id> nextLevel = new Set<Id>();

                String query = 'SELECT Id, Source_Asset__c, Dependent_Asset__c, ' +
                              'Dependency_Type__c, Impact_Level__c, Is_Active__c, ' +
                              'Relationship_Category__c, Dependency_Strength__c, Relationship_Style__c, ' +
                              'Source_Asset__r.Name, Source_Asset__r.Status, Source_Asset__r.Product2.Name, ' +
                              'Dependent_Asset__r.Name, Dependent_Asset__r.Status, Dependent_Asset__r.Product2.Name ' +
                              'FROM Asset_Dependency__c WHERE (Is_Active__c = true OR Is_Active__c = null) AND ';

                if (direction == 'upstream') {
                    query += 'Dependent_Asset__c IN :currentLevel';
                } else if (direction == 'downstream') {
                    query += 'Source_Asset__c IN :currentLevel';
                } else {
                    query += '(Source_Asset__c IN :currentLevel OR Dependent_Asset__c IN :currentLevel)';
                }

                List<Asset_Dependency__c> deps = Database.query(query);
                allCollectedDeps.addAll(deps);

                for (Asset_Dependency__c dep : deps) {
                    if (!processedAssets.contains(dep.Source_Asset__c)) {
                        processedAssets.add(dep.Source_Asset__c);
                        nextLevel.add(dep.Source_Asset__c);
                    }
                    if (!processedAssets.contains(dep.Dependent_Asset__c)) {
                        processedAssets.add(dep.Dependent_Asset__c);
                        nextLevel.add(dep.Dependent_Asset__c);
                    }
                }

                currentLevel = nextLevel;
                if (currentLevel.isEmpty()) break;
            }

            // Bulk-fetch all assets and signals in 2 queries
            Map<Id, Asset> assetMap = getAssetDetailsMap(processedAssets);
            Map<Id, AssetSignals> signalsMap = getBulkAssetSignals(processedAssets);

            // Build nodes
            for (Id assetId : processedAssets) {
                Asset asset = assetMap.get(assetId);
                if (asset != null) {
                    graphData.nodes.add(buildGraphNode(asset, assetId == focusAssetId, signalsMap.get(assetId)));
                }
            }

            // Build edges
            for (Asset_Dependency__c dep : allCollectedDeps) {
                graphData.edges.add(buildGraphEdge(dep));
            }

            return graphData;

        } catch (Exception e) {
            throw new AuraHandledException('Error expanding node: ' + e.getMessage());
        }
    }

    /**
     * Calculate critical path using Dijkstra's algorithm
     */
    @AuraEnabled(cacheable=true)
    public static CriticalPathResult getCriticalPath(Id focusAssetId) {
        try {
            CriticalPathResult result = new CriticalPathResult();
            result.criticalNodes = new List<Id>();
            result.criticalEdges = new List<Id>();

            // Scope query: only fetch dependencies reachable from/to focus asset
            // Use a bounded traversal to collect relevant asset IDs first
            Set<Id> relevantAssetIds = new Set<Id>{focusAssetId};
            Set<Id> frontier = new Set<Id>{focusAssetId};
            Integer maxTraversalDepth = 10;

            for (Integer d = 0; d < maxTraversalDepth && !frontier.isEmpty(); d++) {
                List<Asset_Dependency__c> nearby = [
                    SELECT Source_Asset__c, Dependent_Asset__c
                    FROM Asset_Dependency__c
                    WHERE (Is_Active__c = true OR Is_Active__c = null)
                    AND (Source_Asset__c IN :frontier OR Dependent_Asset__c IN :frontier)
                ];
                Set<Id> nextFrontier = new Set<Id>();
                for (Asset_Dependency__c dep : nearby) {
                    if (!relevantAssetIds.contains(dep.Source_Asset__c)) {
                        nextFrontier.add(dep.Source_Asset__c);
                        relevantAssetIds.add(dep.Source_Asset__c);
                    }
                    if (!relevantAssetIds.contains(dep.Dependent_Asset__c)) {
                        nextFrontier.add(dep.Dependent_Asset__c);
                        relevantAssetIds.add(dep.Dependent_Asset__c);
                    }
                }
                frontier = nextFrontier;
            }

            // Now fetch full dependency data only for reachable assets
            List<Asset_Dependency__c> allDeps = [
                SELECT Id, Source_Asset__c, Dependent_Asset__c,
                       Dependency_Strength__c, Relationship_Category__c
                FROM Asset_Dependency__c
                WHERE (Is_Active__c = true OR Is_Active__c = null)
                AND Source_Asset__c IN :relevantAssetIds
                AND Dependent_Asset__c IN :relevantAssetIds
            ];

            Map<Id, List<PathEdge>> adjacency = new Map<Id, List<PathEdge>>();
            Map<String, Id> edgeMap = new Map<String, Id>();

            for (Asset_Dependency__c dep : allDeps) {
                if (!adjacency.containsKey(dep.Source_Asset__c)) {
                    adjacency.put(dep.Source_Asset__c, new List<PathEdge>());
                }
                Integer weight = getEdgeWeight(dep.Dependency_Strength__c);
                adjacency.get(dep.Source_Asset__c).add(
                    new PathEdge(dep.Dependent_Asset__c, weight)
                );
                edgeMap.put(dep.Source_Asset__c + '_' + dep.Dependent_Asset__c, dep.Id);
            }

            // Find root nodes (no incoming edges within this subgraph)
            Set<Id> rootNodes = new Set<Id>(adjacency.keySet());
            for (Asset_Dependency__c dep : allDeps) {
                rootNodes.remove(dep.Dependent_Asset__c);
            }

            // Run Dijkstra from each root - single pass returns both distances and predecessors
            Id bestRoot = null;
            Integer shortestDistance = 999999999;
            Map<Id, Id> bestPredecessors = new Map<Id, Id>();

            for (Id root : rootNodes) {
                DijkstraResult dr = dijkstra(root, focusAssetId, adjacency);
                Integer dist = dr.distances.get(focusAssetId);
                if (dist != null && dist < shortestDistance) {
                    shortestDistance = dist;
                    bestRoot = root;
                    bestPredecessors = dr.predecessors;
                }
            }

            // Reconstruct path from best root
            if (bestRoot != null) {
                Id current = focusAssetId;
                while (current != null && current != bestRoot) {
                    result.criticalNodes.add(current);
                    Id previous = bestPredecessors.get(current);
                    if (previous != null) {
                        String edgeKey = previous + '_' + current;
                        if (edgeMap.containsKey(edgeKey)) {
                            result.criticalEdges.add(edgeMap.get(edgeKey));
                        }
                    }
                    current = previous;
                }
                if (current != null) {
                    result.criticalNodes.add(current);
                }

                // Reverse to get root -> focus order
                List<Id> reversed = new List<Id>();
                for (Integer i = result.criticalNodes.size() - 1; i >= 0; i--) {
                    reversed.add(result.criticalNodes[i]);
                }
                result.criticalNodes = reversed;
            }

            return result;

        } catch (Exception e) {
            throw new AuraHandledException('Error calculating critical path: ' + e.getMessage());
        }
    }

    /**
     * Unified Dijkstra returning both distances and predecessors in a single pass
     */
    private static DijkstraResult dijkstra(Id start, Id target, Map<Id, List<PathEdge>> adjacency) {
        DijkstraResult dr = new DijkstraResult();
        dr.distances = new Map<Id, Integer>();
        dr.predecessors = new Map<Id, Id>();
        Set<Id> unvisited = new Set<Id>(adjacency.keySet());

        for (Id nodeId : unvisited) {
            dr.distances.put(nodeId, 999999999);
        }
        dr.distances.put(start, 0);

        while (!unvisited.isEmpty()) {
            Id current = getMinDistanceNode(unvisited, dr.distances);
            if (current == null || dr.distances.get(current) == 999999999) break;
            if (current == target) break;

            unvisited.remove(current);

            if (adjacency.containsKey(current)) {
                for (PathEdge edge : adjacency.get(current)) {
                    if (unvisited.contains(edge.targetId)) {
                        Integer newDist = dr.distances.get(current) + edge.weight;
                        if (newDist < dr.distances.get(edge.targetId)) {
                            dr.distances.put(edge.targetId, newDist);
                            dr.predecessors.put(edge.targetId, current);
                        }
                    }
                }
            }
        }

        return dr;
    }

    private class DijkstraResult {
        Map<Id, Integer> distances;
        Map<Id, Id> predecessors;
    }

    private static Id getMinDistanceNode(Set<Id> unvisited, Map<Id, Integer> distances) {
        Id minNode = null;
        Integer minDist = 999999999;
        for (Id nodeId : unvisited) {
            if (distances.get(nodeId) < minDist) {
                minDist = distances.get(nodeId);
                minNode = nodeId;
            }
        }
        return minNode;
    }

    private static Integer getEdgeWeight(String strength) {
        if (strength == 'Hard Stop') return 1;
        if (strength == 'Degraded Service') return 2;
        return 3; // Soft Dependency
    }

    private class PathEdge {
        Id targetId;
        Integer weight;
        PathEdge(Id target, Integer w) {
            this.targetId = target;
            this.weight = w;
        }
    }

    /**
     * Calculate blast radius (downstream impact)
     */
    @AuraEnabled(cacheable=true)
    public static BlastRadiusResult getBlastRadius(Id focusAssetId) {
        BlastRadiusResult result = new BlastRadiusResult();
        result.directlyImpacted = new List<Id>();
        result.indirectlyImpacted = new List<Id>();

        Set<Id> processed = new Set<Id>{focusAssetId};

        // Get direct dependents (1 hop)
        List<Asset_Dependency__c> directDeps = [
            SELECT Dependent_Asset__c
            FROM Asset_Dependency__c
            WHERE Source_Asset__c = :focusAssetId
            AND (Is_Active__c = true OR Is_Active__c = null)
        ];

        for (Asset_Dependency__c dep : directDeps) {
            result.directlyImpacted.add(dep.Dependent_Asset__c);
            processed.add(dep.Dependent_Asset__c);
        }

        // Get indirect dependents (2+ hops)
        Set<Id> nextLevel = new Set<Id>(result.directlyImpacted);
        Integer maxDepth = 10; // Prevent infinite recursion
        Integer depth = 0;

        while (!nextLevel.isEmpty() && depth < maxDepth) {
            Set<Id> currentLevel = nextLevel;
            nextLevel = new Set<Id>();

            List<Asset_Dependency__c> indirectDeps = [
                SELECT Dependent_Asset__c
                FROM Asset_Dependency__c
                WHERE Source_Asset__c IN :currentLevel
                AND (Is_Active__c = true OR Is_Active__c = null)
            ];

            for (Asset_Dependency__c dep : indirectDeps) {
                if (!processed.contains(dep.Dependent_Asset__c)) {
                    result.indirectlyImpacted.add(dep.Dependent_Asset__c);
                    nextLevel.add(dep.Dependent_Asset__c);
                    processed.add(dep.Dependent_Asset__c);
                }
            }

            depth++;
        }

        result.totalImpacted = result.directlyImpacted.size() + result.indirectlyImpacted.size();

        return result;
    }

    /**
     * Wrapper classes
     */
    public class GraphData {
        @AuraEnabled public Id focusAssetId;
        @AuraEnabled public List<GraphNode> nodes = new List<GraphNode>();
        @AuraEnabled public List<GraphEdge> edges = new List<GraphEdge>();
    }

    public class GraphNode {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String assetType;
        @AuraEnabled public String nodeType; // for icon selection
        @AuraEnabled public String status;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public Boolean isFocus;
        @AuraEnabled public AssetSignals signals;
        @AuraEnabled public String owner;
        @AuraEnabled public String site;
        @AuraEnabled public Id parentId;
        @AuraEnabled public String parentName;
    }

    public class GraphEdge {
        @AuraEnabled public Id id;
        @AuraEnabled public Id source;
        @AuraEnabled public Id target;
        @AuraEnabled public String dependencyType;
        @AuraEnabled public String impactLevel;
        @AuraEnabled public String category;
        @AuraEnabled public String strength;
        @AuraEnabled public String style;
        @AuraEnabled public String label;
    }

    public class AssetSignals {
        @AuraEnabled public Integer openWorkOrders = 0;
        @AuraEnabled public Integer openCases = 0;
        @AuraEnabled public Integer activeAlerts = 0;
        @AuraEnabled public List<AlertRecord> alertRecords = new List<AlertRecord>();
    }

    public class AlertRecord {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Datetime effectiveDate;
        @AuraEnabled public Datetime validUntilDate;

        public AlertRecord(SObject ra) {
            this.id = ra.Id;
            this.name = (String) ra.get('Name');
            this.effectiveDate = (Datetime) ra.get('EffectiveDate');
            this.validUntilDate = (Datetime) ra.get('ValidUntilDate');
        }
    }

    public class BlastRadiusResult {
        @AuraEnabled public List<Id> directlyImpacted;
        @AuraEnabled public List<Id> indirectlyImpacted;
        @AuraEnabled public Integer totalImpacted;
    }

    public class CriticalPathResult {
        @AuraEnabled public List<Id> criticalNodes;
        @AuraEnabled public List<Id> criticalEdges;
    }

    /**
     * Search assets for navigation
     */
    @AuraEnabled(cacheable=true)
    public static List<AssetSearchResult> searchAssetsForNav(String searchTerm) {
        try {
            String sanitized = String.escapeSingleQuotes(searchTerm);
            sanitized = sanitized.replaceAll('%', '\\%').replaceAll('_', '\\_');
            String searchPattern = '%' + sanitized + '%';
            List<Asset> assets = [
                SELECT Id, Name, SerialNumber, Product2.Name, Status,
                       AccountId, Account.Name
                FROM Asset
                WHERE (Name LIKE :searchPattern OR SerialNumber LIKE :searchPattern)
                LIMIT 20
            ];

            List<AssetSearchResult> results = new List<AssetSearchResult>();
            for (Asset asset : assets) {
                AssetSearchResult result = new AssetSearchResult();
                result.id = asset.Id;
                result.name = asset.Name;
                result.serialNumber = asset.SerialNumber;
                result.productName = asset.Product2?.Name;
                result.status = asset.Status;
                result.accountName = asset.Account?.Name;
                results.add(result);
            }
            return results;

        } catch (Exception e) {
            throw new AuraHandledException('Error searching assets: ' + e.getMessage());
        }
    }

    /**
     * Get containment hierarchy (breadcrumb) for an asset
     */
    @AuraEnabled(cacheable=true)
    public static List<BreadcrumbItem> getContainmentHierarchy(Id assetId) {
        try {
            List<BreadcrumbItem> breadcrumbs = new List<BreadcrumbItem>();

            Asset currentAsset = [
                SELECT Id, Name, ParentId, Parent.Name, Parent.ParentId,
                       Parent.Parent.Name, Parent.Parent.ParentId,
                       Parent.Parent.Parent.Name, Parent.Parent.Parent.ParentId,
                       Parent.Parent.Parent.Parent.Name, Parent.Parent.Parent.Parent.ParentId,
                       RootAssetId
                FROM Asset
                WHERE Id = :assetId
                LIMIT 1
            ];

            // Build hierarchy from root to current
            List<Asset> hierarchy = new List<Asset>();

            // Add ancestors
            if (currentAsset.Parent?.Parent?.Parent?.Parent?.Name != null) {
                hierarchy.add(new Asset(
                    Id = currentAsset.Parent.Parent.Parent.Parent.ParentId,
                    Name = currentAsset.Parent.Parent.Parent.Parent.Name
                ));
            }
            if (currentAsset.Parent?.Parent?.Parent?.Name != null) {
                hierarchy.add(new Asset(
                    Id = currentAsset.Parent.Parent.Parent.ParentId,
                    Name = currentAsset.Parent.Parent.Parent.Name
                ));
            }
            if (currentAsset.Parent?.Parent?.Name != null) {
                hierarchy.add(new Asset(
                    Id = currentAsset.Parent.Parent.ParentId,
                    Name = currentAsset.Parent.Parent.Name
                ));
            }
            if (currentAsset.Parent?.Name != null) {
                hierarchy.add(new Asset(
                    Id = currentAsset.ParentId,
                    Name = currentAsset.Parent.Name
                ));
            }

            // Add current asset
            hierarchy.add(currentAsset);

            // Convert to breadcrumbs
            for (Asset asset : hierarchy) {
                BreadcrumbItem item = new BreadcrumbItem();
                item.id = asset.Id;
                item.name = asset.Name;
                breadcrumbs.add(item);
            }

            return breadcrumbs;

        } catch (Exception e) {
            throw new AuraHandledException('Error getting hierarchy: ' + e.getMessage());
        }
    }

    public class AssetSearchResult {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String productName;
        @AuraEnabled public String status;
        @AuraEnabled public String accountName;
    }

    public class BreadcrumbItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
    }
}
