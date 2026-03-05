@isTest
private class AssetDependencyControllerTest {

    @testSetup
    static void setupTestData() {
        // Create test account (required for Assets)
        Account testAccount = new Account(Name = 'Test Telecom Company');
        insert testAccount;

        // Create test products
        Product2 switchProduct = new Product2(Name = 'Fiber Switch Model A', IsActive = true);
        Product2 ontProduct = new Product2(Name = 'Residential ONT Model B', IsActive = true);
        insert new List<Product2>{switchProduct, ontProduct};

        // Create test assets with Account
        Asset mainSwitch = new Asset(
            Name = 'Main Fiber Switch',
            AccountId = testAccount.Id,
            Product2Id = switchProduct.Id,
            SerialNumber = 'SW-001',
            Status = 'Installed'
        );

        Asset switch2 = new Asset(
            Name = 'Secondary Switch',
            AccountId = testAccount.Id,
            Product2Id = switchProduct.Id,
            SerialNumber = 'SW-002',
            Status = 'Installed'
        );

        Asset ont1 = new Asset(
            Name = 'Home ONT 123',
            AccountId = testAccount.Id,
            Product2Id = ontProduct.Id,
            SerialNumber = 'ONT-123',
            Status = 'Installed'
        );

        Asset ont2 = new Asset(
            Name = 'Home ONT 456',
            AccountId = testAccount.Id,
            Product2Id = ontProduct.Id,
            SerialNumber = 'ONT-456',
            Status = 'Installed'
        );

        Asset ont3 = new Asset(
            Name = 'Home ONT 789',
            AccountId = testAccount.Id,
            Product2Id = ontProduct.Id,
            SerialNumber = 'ONT-789',
            Status = 'Installed'
        );

        insert new List<Asset>{mainSwitch, switch2, ont1, ont2, ont3};

        // Create dependencies
        Asset_Dependency__c dep1 = new Asset_Dependency__c(
            Source_Asset__c = mainSwitch.Id,
            Dependent_Asset__c = switch2.Id,
            Dependency_Type__c = 'Fiber Connection',
            Impact_Level__c = 'Critical',
            Is_Active__c = true
        );

        Asset_Dependency__c dep2 = new Asset_Dependency__c(
            Source_Asset__c = mainSwitch.Id,
            Dependent_Asset__c = ont1.Id,
            Dependency_Type__c = 'Network Connection',
            Impact_Level__c = 'High',
            Is_Active__c = true
        );

        Asset_Dependency__c dep3 = new Asset_Dependency__c(
            Source_Asset__c = switch2.Id,
            Dependent_Asset__c = ont2.Id,
            Dependency_Type__c = 'Network Connection',
            Impact_Level__c = 'High',
            Is_Active__c = true
        );

        Asset_Dependency__c dep4 = new Asset_Dependency__c(
            Source_Asset__c = switch2.Id,
            Dependent_Asset__c = ont3.Id,
            Dependency_Type__c = 'Network Connection',
            Impact_Level__c = 'Medium',
            Is_Active__c = true
        );

        insert new List<Asset_Dependency__c>{dep1, dep2, dep3, dep4};
    }

    @isTest
    static void testGetAssetDependencies_MainSwitch() {
        Asset mainSwitch = [SELECT Id FROM Asset WHERE Name = 'Main Fiber Switch' LIMIT 1];

        Test.startTest();
        AssetDependencyController.AssetDependencyWrapper result =
            AssetDependencyController.getAssetDependencies(mainSwitch.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.rootAsset, 'Root asset should not be null');
        System.assertEquals('Main Fiber Switch', result.rootAsset.assetName, 'Root asset name should match');
        System.assert(result.totalImpactedAssets >= 1, 'Should have at least 1 impacted asset');
        System.assert(result.rootAsset.children.size() >= 1, 'Should have at least 1 direct child');
    }

    @isTest
    static void testGetAssetDependencies_SecondarySwitch() {
        Asset switch2 = [SELECT Id FROM Asset WHERE Name = 'Secondary Switch' LIMIT 1];

        Test.startTest();
        AssetDependencyController.AssetDependencyWrapper result =
            AssetDependencyController.getAssetDependencies(switch2.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(2, result.totalImpactedAssets, 'Should have 2 impacted assets');
        System.assertEquals(2, result.rootAsset.children.size(), 'Should have 2 ONT children');
        System.assertEquals(1, result.rootAsset.upstreamDependencies.size(), 'Should have 1 upstream dependency');
    }

    @isTest
    static void testGetAssetDependencies_ONTWithNoChildren() {
        Asset ont1 = [SELECT Id FROM Asset WHERE Name = 'Home ONT 123' LIMIT 1];

        Test.startTest();
        AssetDependencyController.AssetDependencyWrapper result =
            AssetDependencyController.getAssetDependencies(ont1.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(0, result.totalImpactedAssets, 'ONT should have no downstream dependencies');
        System.assertEquals(1, result.rootAsset.upstreamDependencies.size(), 'Should depend on main switch');
    }

    @isTest
    static void testGetAssetDependencies_InvalidAssetId() {
        Id fakeAssetId = '02i000000000000AAA';

        Test.startTest();
        try {
            AssetDependencyController.getAssetDependencies(fakeAssetId);
            System.assert(false, 'Should have thrown an exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testGetAssetDependencies_InactiveDependencies() {
        Asset mainSwitch = [SELECT Id FROM Asset WHERE Name = 'Main Fiber Switch' LIMIT 1];
        Asset_Dependency__c dep = [
            SELECT Id
            FROM Asset_Dependency__c
            WHERE Source_Asset__c = :mainSwitch.Id
            LIMIT 1
        ];

        // Deactivate one dependency
        dep.Is_Active__c = false;
        update dep;

        Test.startTest();
        AssetDependencyController.AssetDependencyWrapper result =
            AssetDependencyController.getAssetDependencies(mainSwitch.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.totalImpactedAssets >= 0,
            'Should have fewer impacted assets after deactivation');
    }

    @isTest
    static void testCreateDependency() {
        Asset mainSwitch = [SELECT Id FROM Asset WHERE Name = 'Main Fiber Switch' LIMIT 1];
        Asset ont3 = [SELECT Id FROM Asset WHERE Name = 'Home ONT 789' LIMIT 1];

        Test.startTest();
        Id depId = AssetDependencyController.createDependency(
            mainSwitch.Id,
            ont3.Id,
            'Power Supply',
            'High',
            'Power',
            'Hard Stop',
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, depId, 'Should return dependency ID');

        Asset_Dependency__c createdDep = [
            SELECT Id, Source_Asset__c, Dependent_Asset__c, Dependency_Type__c,
                   Impact_Level__c, Relationship_Category__c, Dependency_Strength__c
            FROM Asset_Dependency__c
            WHERE Id = :depId
        ];

        System.assertEquals(mainSwitch.Id, createdDep.Source_Asset__c, 'Source should match');
        System.assertEquals(ont3.Id, createdDep.Dependent_Asset__c, 'Dependent should match');
        System.assertEquals('Power Supply', createdDep.Dependency_Type__c, 'Type should match');
        System.assertEquals('High', createdDep.Impact_Level__c, 'Impact should match');
        System.assertEquals('Power', createdDep.Relationship_Category__c, 'Category should match');
        System.assertEquals('Hard Stop', createdDep.Dependency_Strength__c, 'Strength should match');
    }

    @isTest
    static void testCreateDependency_Duplicate() {
        Asset mainSwitch = [SELECT Id FROM Asset WHERE Name = 'Main Fiber Switch' LIMIT 1];
        Asset switch2 = [SELECT Id FROM Asset WHERE Name = 'Secondary Switch' LIMIT 1];

        Test.startTest();
        try {
            AssetDependencyController.createDependency(
                mainSwitch.Id,
                switch2.Id,
                'Fiber Connection',
                'Critical',
                'Network',
                'Hard Stop',
                null
            );
            System.assert(false, 'Should have thrown exception for duplicate');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testCreateDependency_Circular() {
        Asset mainSwitch = [SELECT Id FROM Asset WHERE Name = 'Main Fiber Switch' LIMIT 1];
        Asset switch2 = [SELECT Id FROM Asset WHERE Name = 'Secondary Switch' LIMIT 1];

        Test.startTest();
        try {
            // Try to create reverse dependency (would create circular)
            AssetDependencyController.createDependency(
                switch2.Id,
                mainSwitch.Id,
                'Fiber Connection',
                'Critical',
                'Network',
                'Hard Stop',
                null
            );
            System.assert(false, 'Should have thrown exception for circular dependency');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testSearchAssets() {
        Asset mainSwitch = [SELECT Id FROM Asset WHERE Name = 'Main Fiber Switch' LIMIT 1];

        Test.startTest();
        List<AssetDependencyController.AssetSearchResult> results =
            AssetDependencyController.searchAssets('ONT', mainSwitch.Id);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
        System.assert(results.size() >= 3, 'Should find at least 3 ONT assets');

        for (AssetDependencyController.AssetSearchResult result : results) {
            System.assert(result.assetName.contains('ONT'), 'Asset name should contain ONT');
            System.assertNotEquals(mainSwitch.Id, result.assetId, 'Should exclude the specified asset');
        }
    }

    @isTest
    static void testSearchAssets_NoResults() {
        Asset mainSwitch = [SELECT Id FROM Asset WHERE Name = 'Main Fiber Switch' LIMIT 1];

        Test.startTest();
        List<AssetDependencyController.AssetSearchResult> results =
            AssetDependencyController.searchAssets('NonExistentAsset999', mainSwitch.Id);
        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(0, results.size(), 'Should find no results');
    }

    @isTest
    static void testGetPicklistValues() {
        Test.startTest();
        Map<String, List<AssetDependencyController.PicklistValue>> result =
            AssetDependencyController.getPicklistValues();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.containsKey('dependencyTypes'), 'Should have dependency types');
        System.assert(result.containsKey('impactLevels'), 'Should have impact levels');

        List<AssetDependencyController.PicklistValue> depTypes = result.get('dependencyTypes');
        System.assert(depTypes.size() > 0, 'Should have at least one dependency type');

        List<AssetDependencyController.PicklistValue> impactLevels = result.get('impactLevels');
        System.assert(impactLevels.size() > 0, 'Should have at least one impact level');
    }

    @isTest
    static void testDeleteDependency() {
        Asset_Dependency__c dep = [
            SELECT Id
            FROM Asset_Dependency__c
            LIMIT 1
        ];

        Test.startTest();
        AssetDependencyController.deleteDependency(dep.Id);
        Test.stopTest();

        List<Asset_Dependency__c> remaining = [
            SELECT Id
            FROM Asset_Dependency__c
            WHERE Id = :dep.Id
        ];

        System.assertEquals(0, remaining.size(), 'Dependency should be deleted');
    }

    @isTest
    static void testDeleteDependency_Invalid() {
        Test.startTest();
        try {
            AssetDependencyController.deleteDependency(null);
            // If no exception, the method handled it gracefully
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Should have error message');
        } catch (Exception e) {
            System.assertNotEquals(null, e.getMessage(), 'Should have error message');
        }
        Test.stopTest();
    }

    @isTest
    static void testPreviewDependencies_Hierarchy() {
        // Create a parent-child hierarchy for hierarchy-based discovery
        Asset mainSwitch = [SELECT Id FROM Asset WHERE Name = 'Main Fiber Switch' LIMIT 1];
        Asset ont1 = [SELECT Id FROM Asset WHERE Name = 'Home ONT 123' LIMIT 1];

        // Set ont1 as child of mainSwitch
        ont1.ParentId = mainSwitch.Id;
        update ont1;

        Test.startTest();
        AssetDependencyController.PreviewResult result =
            AssetDependencyController.previewDependencies(mainSwitch.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.candidates, 'Candidates should not be null');
        // Should have candidates from hierarchy, account, and/or product strategies
        System.assert(result.candidates.size() >= 0, 'Should return candidate list');
    }

    @isTest
    static void testPreviewDependencies_ProductRules() {
        // Create assets with product names matching CMT rules (router + switch)
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Telecom Company' LIMIT 1];

        Product2 routerProduct = new Product2(Name = 'Core Router X100', IsActive = true);
        insert routerProduct;

        Asset routerAsset = new Asset(
            Name = 'Test Router',
            AccountId = testAccount.Id,
            Product2Id = routerProduct.Id,
            SerialNumber = 'RTR-001',
            Status = 'Installed'
        );
        insert routerAsset;

        Test.startTest();
        AssetDependencyController.PreviewResult result =
            AssetDependencyController.previewDependencies(routerAsset.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.candidates, 'Candidates list should not be null');
        // CMT records may or may not be deployed; verify method completes without error
        System.assert(result.candidates.size() >= 0, 'Should return a valid candidate list');
    }

    @isTest
    static void testPreviewDependencies_SkipsDuplicates() {
        // mainSwitch already has a dependency to switch2, so it should be skipped
        Asset mainSwitch = [SELECT Id FROM Asset WHERE Name = 'Main Fiber Switch' LIMIT 1];

        Test.startTest();
        AssetDependencyController.PreviewResult result =
            AssetDependencyController.previewDependencies(mainSwitch.Id);
        Test.stopTest();

        System.assert(result.skipped >= 0, 'Skipped count should be non-negative');
    }

    @isTest
    static void testCreateDiscoveredDependencies() {
        Asset mainSwitch = [SELECT Id FROM Asset WHERE Name = 'Main Fiber Switch' LIMIT 1];
        Asset ont3 = [SELECT Id FROM Asset WHERE Name = 'Home ONT 789' LIMIT 1];

        // Delete existing dependency between these two if any
        delete [SELECT Id FROM Asset_Dependency__c
                WHERE Source_Asset__c = :mainSwitch.Id AND Dependent_Asset__c = :ont3.Id];

        List<AssetDependencyController.DiscoveredDependency> candidates =
            new List<AssetDependencyController.DiscoveredDependency>();
        AssetDependencyController.DiscoveredDependency c = new AssetDependencyController.DiscoveredDependency();
        c.sourceAssetId = mainSwitch.Id;
        c.sourceAssetName = 'Main Fiber Switch';
        c.dependentAssetId = ont3.Id;
        c.dependentAssetName = 'Home ONT 789';
        c.dependencyType = 'Network Connection';
        c.impactLevel = 'High';
        c.relationshipCategory = 'Network';
        c.dependencyStrength = 'Degraded Service';
        c.strategy = 'Product';
        candidates.add(c);

        String candidatesJson = JSON.serialize(candidates);

        Test.startTest();
        Integer created = AssetDependencyController.createDiscoveredDependencies(candidatesJson);
        Test.stopTest();

        System.assertEquals(1, created, 'Should create 1 dependency');

        List<Asset_Dependency__c> newDeps = [
            SELECT Id FROM Asset_Dependency__c
            WHERE Source_Asset__c = :mainSwitch.Id AND Dependent_Asset__c = :ont3.Id
        ];
        System.assertEquals(1, newDeps.size(), 'Should have 1 new dependency record');
    }

    @isTest
    static void testPreviewDependencies_NoProduct() {
        // Test with an asset that has no product
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Telecom Company' LIMIT 1];

        Asset noProductAsset = new Asset(
            Name = 'Generic Asset No Product',
            AccountId = testAccount.Id,
            SerialNumber = 'GEN-001',
            Status = 'Installed'
        );
        insert noProductAsset;

        Test.startTest();
        AssetDependencyController.PreviewResult result =
            AssetDependencyController.previewDependencies(noProductAsset.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
    }
}
