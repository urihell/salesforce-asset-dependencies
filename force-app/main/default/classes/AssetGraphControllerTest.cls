@isTest
private class AssetGraphControllerTest {

    @testSetup
    static void setupTestData() {
        // Create test account (required for Assets)
        Account testAccount = new Account(Name = 'Test Network Infrastructure Co');
        insert testAccount;

        // Create test products
        Product2 routerProduct = new Product2(Name = 'Core Router CR-5000', IsActive = true);
        Product2 switchProduct = new Product2(Name = 'Fiber Switch XR-2000', IsActive = true);
        Product2 ontProduct = new Product2(Name = 'Residential ONT', IsActive = true);
        insert new List<Product2>{routerProduct, switchProduct, ontProduct};

        // Create test assets with Account
        Asset coreRouter = new Asset(
            Name = 'Core Router - Building A',
            AccountId = testAccount.Id,
            Product2Id = routerProduct.Id,
            SerialNumber = 'CR-001',
            Status = 'Installed'
        );

        Asset mainSwitch = new Asset(
            Name = 'Main Fiber Switch - Floor 1',
            AccountId = testAccount.Id,
            Product2Id = switchProduct.Id,
            SerialNumber = 'FS-101',
            Status = 'Installed'
        );

        Asset backupSwitch = new Asset(
            Name = 'Backup Fiber Switch - Floor 2',
            AccountId = testAccount.Id,
            Product2Id = switchProduct.Id,
            SerialNumber = 'FS-102',
            Status = 'Installed'
        );

        Asset ont1 = new Asset(
            Name = 'ONT - Residence 123',
            AccountId = testAccount.Id,
            Product2Id = ontProduct.Id,
            SerialNumber = 'ONT-001',
            Status = 'Installed',
            ParentId = null
        );

        Asset ont2 = new Asset(
            Name = 'ONT - Residence 456',
            AccountId = testAccount.Id,
            Product2Id = ontProduct.Id,
            SerialNumber = 'ONT-002',
            Status = 'Installed'
        );

        insert new List<Asset>{coreRouter, mainSwitch, backupSwitch, ont1, ont2};

        // Update ont1 to have mainSwitch as parent (for hierarchy testing)
        ont1.ParentId = mainSwitch.Id;
        update ont1;

        // Create dependencies with new fields (omitting Relationship_Style__c as it may have restricted values)
        List<Asset_Dependency__c> dependencies = new List<Asset_Dependency__c>{
            new Asset_Dependency__c(
                Source_Asset__c = coreRouter.Id,
                Dependent_Asset__c = mainSwitch.Id,
                Dependency_Type__c = 'Fiber Connection',
                Impact_Level__c = 'Critical',
                Relationship_Category__c = 'Network',
                Dependency_Strength__c = 'Hard Stop',
                Is_Active__c = true
            ),
            new Asset_Dependency__c(
                Source_Asset__c = mainSwitch.Id,
                Dependent_Asset__c = ont1.Id,
                Dependency_Type__c = 'Network Connection',
                Impact_Level__c = 'High',
                Relationship_Category__c = 'Network',
                Dependency_Strength__c = 'Degraded Service',
                Is_Active__c = true
            ),
            new Asset_Dependency__c(
                Source_Asset__c = backupSwitch.Id,
                Dependent_Asset__c = ont2.Id,
                Dependency_Type__c = 'Network Connection',
                Impact_Level__c = 'Medium',
                Relationship_Category__c = 'Network',
                Dependency_Strength__c = 'Soft Dependency',
                Is_Active__c = true
            )
        };

        insert dependencies;
    }

    @isTest
    static void testGetGraphData() {
        Asset mainSwitch = [SELECT Id FROM Asset WHERE Name = 'Main Fiber Switch - Floor 1' LIMIT 1];

        Test.startTest();
        AssetGraphController.GraphData result = AssetGraphController.getGraphData(mainSwitch.Id, 2);
        Test.stopTest();

        System.assertNotEquals(null, result, 'GraphData should not be null');
        System.assertNotEquals(null, result.nodes, 'Nodes should not be null');
        System.assertNotEquals(null, result.edges, 'Edges should not be null');
        System.assertEquals(mainSwitch.Id, result.focusAssetId, 'Focus asset ID should match');

        // Should have at least the focus node + connected nodes
        System.assert(result.nodes.size() >= 2, 'Should have at least 2 nodes');
        System.assert(result.edges.size() >= 1, 'Should have at least 1 edge');

        // Find focus node
        Boolean hasFocusNode = false;
        for (AssetGraphController.GraphNode node : result.nodes) {
            if (node.isFocus) {
                hasFocusNode = true;
                System.assertEquals('Main Fiber Switch - Floor 1', node.name, 'Focus node name should match');
                break;
            }
        }
        System.assert(hasFocusNode, 'Should have a focus node');
    }

    @isTest
    static void testGetGraphDataWithInactiveDependencies() {
        Asset mainSwitch = [SELECT Id FROM Asset WHERE Name = 'Main Fiber Switch - Floor 1' LIMIT 1];
        Asset_Dependency__c dep = [
            SELECT Id
            FROM Asset_Dependency__c
            WHERE Source_Asset__c = :mainSwitch.Id
            LIMIT 1
        ];

        dep.Is_Active__c = false;
        update dep;

        Test.startTest();
        AssetGraphController.GraphData result = AssetGraphController.getGraphData(mainSwitch.Id, 1);
        Test.stopTest();

        System.assertNotEquals(null, result, 'GraphData should not be null');
        // Should still work but exclude inactive dependencies
    }

    @isTest
    static void testGetGraphDataInvalidAsset() {
        Id fakeAssetId = '02i000000000000AAA';

        Test.startTest();
        try {
            AssetGraphController.getGraphData(fakeAssetId, 1);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Error getting graph data'), 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testExpandNode() {
        Asset coreRouter = [SELECT Id FROM Asset WHERE Name = 'Core Router - Building A' LIMIT 1];
        Asset mainSwitch = [SELECT Id FROM Asset WHERE Name = 'Main Fiber Switch - Floor 1' LIMIT 1];

        Test.startTest();
        AssetGraphController.GraphData result = AssetGraphController.expandNode(
            coreRouter.Id,
            mainSwitch.Id,
            1,
            'downstream'
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.nodes, 'Nodes should not be null');
        System.assertNotEquals(null, result.edges, 'Edges should not be null');
    }

    @isTest
    static void testExpandNodeUpstream() {
        Asset mainSwitch = [SELECT Id FROM Asset WHERE Name = 'Main Fiber Switch - Floor 1' LIMIT 1];
        Asset ont1 = [SELECT Id FROM Asset WHERE Name = 'ONT - Residence 123' LIMIT 1];

        Test.startTest();
        AssetGraphController.GraphData result = AssetGraphController.expandNode(
            ont1.Id,
            mainSwitch.Id,
            1,
            'upstream'
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @isTest
    static void testExpandNodeBothDirections() {
        Asset mainSwitch = [SELECT Id FROM Asset WHERE Name = 'Main Fiber Switch - Floor 1' LIMIT 1];

        Test.startTest();
        AssetGraphController.GraphData result = AssetGraphController.expandNode(
            mainSwitch.Id,
            mainSwitch.Id,
            1,
            'both'
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @isTest
    static void testGetCriticalPath() {
        Asset mainSwitch = [SELECT Id FROM Asset WHERE Name = 'Main Fiber Switch - Floor 1' LIMIT 1];

        Test.startTest();
        AssetGraphController.CriticalPathResult result = AssetGraphController.getCriticalPath(mainSwitch.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.criticalNodes, 'Critical nodes should not be null');
        System.assertNotEquals(null, result.criticalEdges, 'Critical edges should not be null');
    }

    @isTest
    static void testGetBlastRadius() {
        Asset mainSwitch = [SELECT Id FROM Asset WHERE Name = 'Main Fiber Switch - Floor 1' LIMIT 1];

        Test.startTest();
        AssetGraphController.BlastRadiusResult result = AssetGraphController.getBlastRadius(mainSwitch.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.directlyImpacted, 'Directly impacted should not be null');
        System.assertNotEquals(null, result.indirectlyImpacted, 'Indirectly impacted should not be null');
        System.assert(result.totalImpacted >= 0, 'Total impacted should be non-negative');

        // Main switch has ont1 as direct dependent
        System.assert(result.directlyImpacted.size() >= 1, 'Should have at least 1 directly impacted asset');
    }

    @isTest
    static void testGetBlastRadiusNoDownstream() {
        Asset ont1 = [SELECT Id FROM Asset WHERE Name = 'ONT - Residence 123' LIMIT 1];

        Test.startTest();
        AssetGraphController.BlastRadiusResult result = AssetGraphController.getBlastRadius(ont1.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.totalImpacted, 'ONT should have no downstream impact');
    }

    @isTest
    static void testSearchAssetsForNav() {
        Test.startTest();
        List<AssetGraphController.AssetSearchResult> results =
            AssetGraphController.searchAssetsForNav('ONT');
        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
        System.assert(results.size() >= 2, 'Should find at least 2 ONT assets');

        for (AssetGraphController.AssetSearchResult result : results) {
            System.assert(result.name.contains('ONT'), 'Result should contain ONT');
        }
    }

    @isTest
    static void testSearchAssetsForNavNoResults() {
        Test.startTest();
        List<AssetGraphController.AssetSearchResult> results =
            AssetGraphController.searchAssetsForNav('NonExistentAsset12345');
        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(0, results.size(), 'Should find no results');
    }

    @isTest
    static void testGetContainmentHierarchy() {
        Asset ont1 = [SELECT Id FROM Asset WHERE Name = 'ONT - Residence 123' LIMIT 1];

        Test.startTest();
        List<AssetGraphController.BreadcrumbItem> result =
            AssetGraphController.getContainmentHierarchy(ont1.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        // ont1 has mainSwitch as parent, so should have at least 2 items
        System.assert(result.size() >= 2, 'Should have at least 2 breadcrumb items');
    }

    @isTest
    static void testGetContainmentHierarchyNoParent() {
        Asset coreRouter = [SELECT Id FROM Asset WHERE Name = 'Core Router - Building A' LIMIT 1];

        Test.startTest();
        List<AssetGraphController.BreadcrumbItem> result =
            AssetGraphController.getContainmentHierarchy(coreRouter.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(1, result.size(), 'Should have only the asset itself');
    }

    @isTest
    static void testGraphNodeSignals() {
        // This tests the signals functionality (WorkOrders and Cases)
        Asset mainSwitch = [SELECT Id FROM Asset WHERE Name = 'Main Fiber Switch - Floor 1' LIMIT 1];

        Test.startTest();
        AssetGraphController.GraphData result = AssetGraphController.getGraphData(mainSwitch.Id, 1);
        Test.stopTest();

        // Should not throw error even if WorkOrder/Case objects are not available
        System.assertNotEquals(null, result, 'Result should not be null');

        for (AssetGraphController.GraphNode node : result.nodes) {
            System.assertNotEquals(null, node.signals, 'Signals should not be null');
            System.assert(node.signals.openWorkOrders >= 0, 'Open work orders should be non-negative');
            System.assert(node.signals.openCases >= 0, 'Open cases should be non-negative');
            System.assert(node.signals.activeAlerts >= 0, 'Active alerts should be non-negative');
        }
    }

    @isTest
    static void testGraphEdgeProperties() {
        Asset mainSwitch = [SELECT Id FROM Asset WHERE Name = 'Main Fiber Switch - Floor 1' LIMIT 1];

        Test.startTest();
        AssetGraphController.GraphData result = AssetGraphController.getGraphData(mainSwitch.Id, 2);
        Test.stopTest();

        System.assert(result.edges.size() > 0, 'Should have edges');

        for (AssetGraphController.GraphEdge edge : result.edges) {
            System.assertNotEquals(null, edge.id, 'Edge ID should not be null');
            System.assertNotEquals(null, edge.source, 'Edge source should not be null');
            System.assertNotEquals(null, edge.target, 'Edge target should not be null');
            System.assertNotEquals(null, edge.label, 'Edge label should not be null');
        }
    }
}
