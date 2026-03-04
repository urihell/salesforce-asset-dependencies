public with sharing class AssetDependencyController {

    /**
     * Retrieves the complete dependency tree for a given asset
     * @param assetId The ID of the asset to get dependencies for
     * @return AssetDependencyWrapper containing the dependency hierarchy
     */
    @AuraEnabled(cacheable=true)
    public static AssetDependencyWrapper getAssetDependencies(Id assetId) {
        try {
            // Get the root asset
            Asset rootAsset = [
                SELECT Id, Name, Product2.Name, SerialNumber, Status
                FROM Asset
                WHERE Id = :assetId
                LIMIT 1
            ];

            AssetDependencyWrapper wrapper = new AssetDependencyWrapper();
            wrapper.rootAsset = buildAssetNode(rootAsset);
            wrapper.totalImpactedAssets = 0;

            // Get all dependencies where this asset is the source
            Map<Id, List<Asset_Dependency__c>> dependencyMap = new Map<Id, List<Asset_Dependency__c>>();
            Set<Id> processedAssets = new Set<Id>{assetId};
            Set<Id> assetsToProcess = new Set<Id>{assetId};

            // Build the dependency map
            List<Asset_Dependency__c> allDependencies = [
                SELECT Id, Source_Asset__c, Dependent_Asset__c,
                       Dependency_Type__c, Impact_Level__c, Is_Active__c,
                       Dependent_Asset__r.Name,
                       Dependent_Asset__r.Product2.Name,
                       Dependent_Asset__r.SerialNumber,
                       Dependent_Asset__r.Status,
                       Source_Asset__r.Name,
                       Source_Asset__r.Product2.Name,
                       Source_Asset__r.SerialNumber,
                       Source_Asset__r.Status
                FROM Asset_Dependency__c
                WHERE Is_Active__c = true
                AND (Source_Asset__c = :assetId
                     OR Dependent_Asset__c = :assetId)
            ];

            // Process downstream dependencies (assets that depend on this one)
            wrapper.rootAsset.children = buildDependencyTree(assetId, allDependencies, processedAssets, true);
            wrapper.totalImpactedAssets = processedAssets.size() - 1; // Exclude root asset

            // Process upstream dependencies (assets this one depends on)
            wrapper.rootAsset.upstreamDependencies = buildDependencyTree(assetId, allDependencies, new Set<Id>{assetId}, false);

            return wrapper;

        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving asset dependencies: ' + e.getMessage());
        }
    }

    /**
     * Recursively builds the dependency tree
     */
    private static List<AssetNode> buildDependencyTree(
        Id currentAssetId,
        List<Asset_Dependency__c> allDependencies,
        Set<Id> processedAssets,
        Boolean downstream
    ) {
        List<AssetNode> nodes = new List<AssetNode>();

        for (Asset_Dependency__c dep : allDependencies) {
            Id nextAssetId;
            Asset nextAsset;

            if (downstream && dep.Source_Asset__c == currentAssetId) {
                // Downstream: assets that depend on current asset
                nextAssetId = dep.Dependent_Asset__c;
                nextAsset = dep.Dependent_Asset__r;
            } else if (!downstream && dep.Dependent_Asset__c == currentAssetId) {
                // Upstream: assets that current asset depends on
                nextAssetId = dep.Source_Asset__c;
                nextAsset = dep.Source_Asset__r;
            } else {
                continue;
            }

            // Avoid circular dependencies
            if (processedAssets.contains(nextAssetId)) {
                continue;
            }

            processedAssets.add(nextAssetId);

            AssetNode node = buildAssetNode(nextAsset);
            node.dependencyType = dep.Dependency_Type__c;
            node.impactLevel = dep.Impact_Level__c;
            node.dependencyId = dep.Id;

            // Recursively get children
            node.children = buildDependencyTree(nextAssetId, allDependencies, processedAssets, downstream);

            nodes.add(node);
        }

        return nodes;
    }

    /**
     * Builds an AssetNode from an Asset record
     */
    private static AssetNode buildAssetNode(Asset asset) {
        AssetNode node = new AssetNode();
        node.assetId = asset.Id;
        node.assetName = asset.Name;
        node.productName = asset.Product2?.Name;
        node.serialNumber = asset.SerialNumber;
        node.status = asset.Status;
        node.children = new List<AssetNode>();
        return node;
    }

    /**
     * Wrapper classes for the response
     */
    public class AssetDependencyWrapper {
        @AuraEnabled public AssetNode rootAsset;
        @AuraEnabled public Integer totalImpactedAssets;
        @AuraEnabled public List<AssetNode> upstreamDependencies;
    }

    public class AssetNode {
        @AuraEnabled public Id assetId;
        @AuraEnabled public String assetName;
        @AuraEnabled public String productName;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String dependencyType;
        @AuraEnabled public String impactLevel;
        @AuraEnabled public Id dependencyId;
        @AuraEnabled public List<AssetNode> children;
        @AuraEnabled public List<AssetNode> upstreamDependencies;
    }

    /**
     * Creates a new asset dependency relationship
     * @param sourceAssetId The asset that others depend on
     * @param dependentAssetId The asset that depends on the source
     * @param dependencyType Type of dependency
     * @param impactLevel Impact level if source fails
     * @param relationshipCategory Category of the relationship
     * @param dependencyStrength Strength of the dependency
     * @return ID of the created dependency record
     */
    @AuraEnabled
    public static Id createDependency(
        Id sourceAssetId,
        Id dependentAssetId,
        String dependencyType,
        String impactLevel,
        String relationshipCategory,
        String dependencyStrength,
        String relationshipStyle
    ) {
        try {
            // Check for duplicate
            List<Asset_Dependency__c> existing = [
                SELECT Id
                FROM Asset_Dependency__c
                WHERE Source_Asset__c = :sourceAssetId
                AND Dependent_Asset__c = :dependentAssetId
                AND Is_Active__c = true
                LIMIT 1
            ];

            if (!existing.isEmpty()) {
                throw new AuraHandledException('A dependency between these assets already exists.');
            }

            // Check for reverse dependency (would create circular)
            List<Asset_Dependency__c> reverse = [
                SELECT Id
                FROM Asset_Dependency__c
                WHERE Source_Asset__c = :dependentAssetId
                AND Dependent_Asset__c = :sourceAssetId
                AND Is_Active__c = true
                LIMIT 1
            ];

            if (!reverse.isEmpty()) {
                throw new AuraHandledException('Cannot create circular dependency. A reverse dependency already exists.');
            }

            Asset_Dependency__c newDep = new Asset_Dependency__c(
                Source_Asset__c = sourceAssetId,
                Dependent_Asset__c = dependentAssetId,
                Dependency_Type__c = dependencyType,
                Impact_Level__c = impactLevel,
                Relationship_Category__c = relationshipCategory,
                Dependency_Strength__c = dependencyStrength,
                Relationship_Style__c = relationshipStyle,
                Is_Active__c = true
            );

            insert newDep;
            return newDep.Id;

        } catch (DmlException e) {
            throw new AuraHandledException('Error creating dependency: ' + e.getMessage());
        }
    }

    /**
     * Searches for assets by name
     * @param searchTerm The search term
     * @param excludeAssetId Asset ID to exclude from results
     * @return List of matching assets
     */
    @AuraEnabled(cacheable=true)
    public static List<AssetSearchResult> searchAssets(String searchTerm, Id excludeAssetId) {
        try {
            String sanitized = String.escapeSingleQuotes(searchTerm);
            sanitized = sanitized.replaceAll('%', '\\%').replaceAll('_', '\\_');
            String searchPattern = '%' + sanitized + '%';
            List<AssetSearchResult> results = new List<AssetSearchResult>();

            List<Asset> assets = [
                SELECT Id, Name, Product2.Name, SerialNumber, Status
                FROM Asset
                WHERE Name LIKE :searchPattern
                AND Id != :excludeAssetId
                ORDER BY Name
                LIMIT 50
            ];

            for (Asset a : assets) {
                AssetSearchResult result = new AssetSearchResult();
                result.assetId = a.Id;
                result.assetName = a.Name;
                result.productName = a.Product2?.Name;
                result.serialNumber = a.SerialNumber;
                result.status = a.Status;
                results.add(result);
            }

            return results;

        } catch (Exception e) {
            throw new AuraHandledException('Error searching assets: ' + e.getMessage());
        }
    }

    /**
     * Gets picklist values for dependency fields
     * @return Map of field name to list of values
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, List<PicklistValue>> getPicklistValues() {
        Map<String, List<PicklistValue>> result = new Map<String, List<PicklistValue>>();

        Schema.DescribeFieldResult dependencyTypeField =
            Asset_Dependency__c.Dependency_Type__c.getDescribe();
        Schema.DescribeFieldResult impactLevelField =
            Asset_Dependency__c.Impact_Level__c.getDescribe();

        result.put('dependencyTypes', convertPicklistValues(dependencyTypeField.getPicklistValues()));
        result.put('impactLevels', convertPicklistValues(impactLevelField.getPicklistValues()));

        return result;
    }

    private static List<PicklistValue> convertPicklistValues(List<Schema.PicklistEntry> entries) {
        List<PicklistValue> values = new List<PicklistValue>();
        for (Schema.PicklistEntry entry : entries) {
            if (entry.isActive()) {
                values.add(new PicklistValue(entry.getLabel(), entry.getValue()));
            }
        }
        return values;
    }

    /**
     * Deletes a dependency relationship
     * @param dependencyId The ID of the dependency to delete
     */
    @AuraEnabled
    public static void deleteDependency(Id dependencyId) {
        try {
            delete [SELECT Id FROM Asset_Dependency__c WHERE Id = :dependencyId];
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting dependency: ' + e.getMessage());
        }
    }

    /**
     * Previews discovered dependency candidates without creating them.
     * Returns a list of DiscoveredDependency wrappers for user review.
     * @param assetId The focus asset to discover dependencies for
     * @return PreviewResult with candidates and skipped count
     */
    @AuraEnabled
    public static PreviewResult previewDependencies(Id assetId) {
        try {
            Asset focusAsset = [
                SELECT Id, Name, AccountId, ParentId, Parent.Name, RootAssetId, Product2.Name
                FROM Asset
                WHERE Id = :assetId
                LIMIT 1
            ];

            // Collect existing dependencies for dedup
            Set<String> existingKeys = new Set<String>();
            for (Asset_Dependency__c dep : [
                SELECT Source_Asset__c, Dependent_Asset__c
                FROM Asset_Dependency__c
                WHERE (Source_Asset__c = :assetId OR Dependent_Asset__c = :assetId)
                AND Is_Active__c = true
            ]) {
                existingKeys.add(dep.Source_Asset__c + '_' + dep.Dependent_Asset__c);
            }

            // Build a map of asset Ids to Names for display
            Set<Id> assetIds = new Set<Id>{ assetId };
            List<DiscoveredDependency> candidates = new List<DiscoveredDependency>();
            Integer skipped = 0;

            // Strategy A: Hierarchy (ParentId)
            List<Asset> children = [
                SELECT Id, Name FROM Asset
                WHERE ParentId = :assetId
            ];
            for (Asset child : children) {
                assetIds.add(child.Id);
                String key = assetId + '_' + child.Id;
                if (existingKeys.contains(key)) {
                    skipped++;
                } else {
                    candidates.add(buildCandidate(assetId, focusAsset.Name, child.Id, child.Name,
                        'Network Connection', 'High', 'Structural', 'Degraded Service', 'Hierarchy'));
                    existingKeys.add(key);
                }
            }

            if (focusAsset.ParentId != null) {
                String key = focusAsset.ParentId + '_' + assetId;
                if (existingKeys.contains(key)) {
                    skipped++;
                } else {
                    candidates.add(buildCandidate(focusAsset.ParentId, focusAsset.Parent.Name, assetId, focusAsset.Name,
                        'Network Connection', 'High', 'Structural', 'Degraded Service', 'Hierarchy'));
                    existingKeys.add(key);
                }
            }

            // Strategy B: Shared Account
            if (focusAsset.AccountId != null) {
                List<Asset> coLocated = [
                    SELECT Id, Name FROM Asset
                    WHERE AccountId = :focusAsset.AccountId
                    AND Id != :assetId
                    AND ParentId != :assetId
                    LIMIT 100
                ];
                for (Asset peer : coLocated) {
                    if (peer.Id == focusAsset.ParentId) continue;
                    String key = assetId + '_' + peer.Id;
                    String reverseKey = peer.Id + '_' + assetId;
                    if (existingKeys.contains(key) || existingKeys.contains(reverseKey)) {
                        skipped++;
                    } else {
                        candidates.add(buildCandidate(assetId, focusAsset.Name, peer.Id, peer.Name,
                            'Other', 'Low', 'Structural', 'Soft Dependency', 'Account'));
                        existingKeys.add(key);
                    }
                }
            }

            // Strategy C: Product-Based Rules
            if (focusAsset.AccountId != null && focusAsset.Product2?.Name != null) {
                String focusProduct = focusAsset.Product2.Name.toLowerCase();
                List<Asset> accountAssets = [
                    SELECT Id, Name, Product2.Name FROM Asset
                    WHERE AccountId = :focusAsset.AccountId
                    AND Id != :assetId
                    AND Product2Id != null
                    LIMIT 200
                ];

                for (Asset peer : accountAssets) {
                    String peerProduct = peer.Product2.Name.toLowerCase();
                    ProductRule rule = matchProductRule(focusProduct, peerProduct);
                    if (rule == null) continue;

                    Id sourceId = rule.focusIsSource ? assetId : peer.Id;
                    String sourceName = rule.focusIsSource ? focusAsset.Name : peer.Name;
                    Id dependentId = rule.focusIsSource ? peer.Id : assetId;
                    String dependentName = rule.focusIsSource ? peer.Name : focusAsset.Name;
                    String key = sourceId + '_' + dependentId;
                    if (existingKeys.contains(key)) {
                        skipped++;
                    } else {
                        candidates.add(buildCandidate(sourceId, sourceName, dependentId, dependentName,
                            rule.depType, rule.impact, rule.category, rule.strength, 'Product'));
                        existingKeys.add(key);
                    }
                }
            }

            PreviewResult result = new PreviewResult();
            result.candidates = candidates;
            result.skipped = skipped;
            return result;

        } catch (Exception e) {
            throw new AuraHandledException('Error previewing dependencies: ' + e.getMessage());
        }
    }

    /**
     * Creates dependency records from a JSON array of selected candidates.
     * @param candidatesJson JSON string of DiscoveredDependency objects
     * @return Number of records created
     */
    @AuraEnabled
    public static Integer createDiscoveredDependencies(String candidatesJson) {
        try {
            List<DiscoveredDependency> candidates =
                (List<DiscoveredDependency>) JSON.deserialize(candidatesJson, List<DiscoveredDependency>.class);

            List<Asset_Dependency__c> toInsert = new List<Asset_Dependency__c>();
            for (DiscoveredDependency c : candidates) {
                toInsert.add(buildDep(c.sourceAssetId, c.dependentAssetId,
                    c.dependencyType, c.impactLevel, c.relationshipCategory, c.dependencyStrength));
            }

            if (!toInsert.isEmpty()) {
                insert toInsert;
            }
            return toInsert.size();
        } catch (Exception e) {
            throw new AuraHandledException('Error creating dependencies: ' + e.getMessage());
        }
    }

    private static DiscoveredDependency buildCandidate(
        Id sourceId, String sourceName, Id dependentId, String dependentName,
        String depType, String impact, String category, String strength, String strategy
    ) {
        DiscoveredDependency d = new DiscoveredDependency();
        d.sourceAssetId = sourceId;
        d.sourceAssetName = sourceName;
        d.dependentAssetId = dependentId;
        d.dependentAssetName = dependentName;
        d.dependencyType = depType;
        d.impactLevel = impact;
        d.relationshipCategory = category;
        d.dependencyStrength = strength;
        d.strategy = strategy;
        return d;
    }

    private static Asset_Dependency__c buildDep(Id sourceId, Id dependentId, String depType, String impact, String category, String strength) {
        return new Asset_Dependency__c(
            Source_Asset__c = sourceId,
            Dependent_Asset__c = dependentId,
            Dependency_Type__c = depType,
            Impact_Level__c = impact,
            Relationship_Category__c = category,
            Dependency_Strength__c = strength,
            Is_Active__c = true
        );
    }

    private static ProductRule matchProductRule(String focusProduct, String peerProduct) {
        // Router → Switch
        if (focusProduct.contains('router') && (peerProduct.contains('switch'))) {
            return new ProductRule(true, 'Fiber Connection', 'Critical', 'Network', 'Hard Stop');
        }
        if (peerProduct.contains('router') && (focusProduct.contains('switch'))) {
            return new ProductRule(false, 'Fiber Connection', 'Critical', 'Network', 'Hard Stop');
        }
        // Switch → ONT/Modem
        if (focusProduct.contains('switch') && (peerProduct.contains('ont') || peerProduct.contains('modem'))) {
            return new ProductRule(true, 'Network Connection', 'High', 'Network', 'Degraded Service');
        }
        if (peerProduct.contains('switch') && (focusProduct.contains('ont') || focusProduct.contains('modem'))) {
            return new ProductRule(false, 'Network Connection', 'High', 'Network', 'Degraded Service');
        }
        // Server → Switch/Router
        if (focusProduct.contains('server') && (peerProduct.contains('switch') || peerProduct.contains('router'))) {
            return new ProductRule(true, 'Data Feed', 'Critical', 'Data', 'Hard Stop');
        }
        if (peerProduct.contains('server') && (focusProduct.contains('switch') || focusProduct.contains('router'))) {
            return new ProductRule(false, 'Data Feed', 'Critical', 'Data', 'Hard Stop');
        }
        return null;
    }

    private class ProductRule {
        Boolean focusIsSource;
        String depType;
        String impact;
        String category;
        String strength;

        ProductRule(Boolean focusIsSource, String depType, String impact, String category, String strength) {
            this.focusIsSource = focusIsSource;
            this.depType = depType;
            this.impact = impact;
            this.category = category;
            this.strength = strength;
        }
    }

    public class DiscoveryResult {
        @AuraEnabled public Integer created = 0;
        @AuraEnabled public Integer skipped = 0;
    }

    public class PreviewResult {
        @AuraEnabled public List<DiscoveredDependency> candidates;
        @AuraEnabled public Integer skipped = 0;
    }

    public class DiscoveredDependency {
        @AuraEnabled public Id sourceAssetId;
        @AuraEnabled public String sourceAssetName;
        @AuraEnabled public Id dependentAssetId;
        @AuraEnabled public String dependentAssetName;
        @AuraEnabled public String dependencyType;
        @AuraEnabled public String impactLevel;
        @AuraEnabled public String relationshipCategory;
        @AuraEnabled public String dependencyStrength;
        @AuraEnabled public String strategy;
    }

    public class AssetSearchResult {
        @AuraEnabled public Id assetId;
        @AuraEnabled public String assetName;
        @AuraEnabled public String productName;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String status;
    }

    public class PicklistValue {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public PicklistValue(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
}
