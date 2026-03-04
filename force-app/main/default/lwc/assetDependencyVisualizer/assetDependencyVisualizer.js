import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getAssetDependencies from '@salesforce/apex/AssetDependencyController.getAssetDependencies';
import searchAssets from '@salesforce/apex/AssetDependencyController.searchAssets';
import getPicklistValues from '@salesforce/apex/AssetDependencyController.getPicklistValues';
import createDependency from '@salesforce/apex/AssetDependencyController.createDependency';
import deleteDependency from '@salesforce/apex/AssetDependencyController.deleteDependency';

const SEARCH_DEBOUNCE_MS = 300;

export default class AssetDependencyVisualizer extends NavigationMixin(LightningElement) {
    @api recordId;

    rootAsset;
    totalImpactedAssets = 0;
    upstreamDependencies = [];
    error;
    isLoading = true;
    viewMode = 'list';
    filterMode = 'complete';

    showImpactSummary = true;
    showUpstream = true;
    showDownstream = true;

    showModal = false;
    searchTerm = '';
    searchResults = [];
    selectedAssetId;
    selectedAssetName;
    dependencyType = 'Network Connection';
    impactLevel = 'Medium';
    isCreating = false;
    relationshipDirection = 'downstream';

    dependencyTypes = [];
    impactLevels = [];

    _searchDebounceTimer;

    wiredDependenciesResult;

    get filterOptions() {
        return [
            { label: 'Complete View', value: 'complete' },
            { label: 'Dependent On (Upstream)', value: 'dependenton' },
            { label: 'Depends On It (Downstream)', value: 'dependentat' }
        ];
    }

    @wire(getAssetDependencies, { assetId: '$recordId' })
    wiredDependencies(result) {
        this.wiredDependenciesResult = result;
        this.isLoading = false;
        if (result.data) {
            this.rootAsset = result.data.rootAsset;
            this.totalImpactedAssets = result.data.totalImpactedAssets;
            this.upstreamDependencies = result.data.rootAsset.upstreamDependencies || [];
            this.error = undefined;
        } else if (result.error) {
            this.error = result.error;
            this.rootAsset = undefined;
            this.showError(result.error);
        }
    }

    @wire(getPicklistValues)
    wiredPicklists({ error, data }) {
        if (data) {
            this.dependencyTypes = data.dependencyTypes || [];
            this.impactLevels = data.impactLevels || [];
        } else if (error) {
            console.error('Error loading picklist values', error);
        }
    }

    get hasDownstreamDependencies() {
        return this.rootAsset?.children && this.rootAsset.children.length > 0;
    }

    get hasUpstreamDependencies() {
        return this.upstreamDependencies && this.upstreamDependencies.length > 0;
    }

    get impactSummary() {
        if (!this.hasDownstreamDependencies) {
            return 'No dependent assets found';
        }
        return `${this.totalImpactedAssets} asset${this.totalImpactedAssets !== 1 ? 's' : ''} would be impacted`;
    }

    get impactClass() {
        if (this.totalImpactedAssets === 0) return 'impact-none';
        if (this.totalImpactedAssets <= 5) return 'impact-low';
        if (this.totalImpactedAssets <= 20) return 'impact-medium';
        return 'impact-high';
    }

    get isListView() {
        return this.viewMode === 'list';
    }

    get isTreeView() {
        return this.viewMode === 'tree';
    }

    get listViewClass() {
        return this.isListView ? 'view-button active' : 'view-button';
    }

    get treeViewClass() {
        return this.isTreeView ? 'view-button active' : 'view-button';
    }

    get showUpstreamSection() {
        return this.filterMode === 'complete' || this.filterMode === 'dependenton';
    }

    get showDownstreamSection() {
        return this.filterMode === 'complete' || this.filterMode === 'dependentat';
    }

    get showCurrentAsset() {
        return this.filterMode === 'complete';
    }

    get modalTitle() {
        return this.relationshipDirection === 'downstream'
            ? 'Add Dependent Asset'
            : 'Add Dependency';
    }

    get modalDescription() {
        return this.relationshipDirection === 'downstream'
            ? 'Select an asset that depends on the current asset'
            : 'Select an asset that the current asset depends on';
    }

    get dependencyTypeOptions() {
        return this.dependencyTypes.map(dt => ({ label: dt.label, value: dt.value }));
    }

    get impactLevelOptions() {
        return this.impactLevels.map(il => ({ label: il.label, value: il.value }));
    }

    get upstreamIcon() {
        return this.showUpstream ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get downstreamIcon() {
        return this.showDownstream ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get impactSummaryIcon() {
        return this.showImpactSummary ? 'utility:chevrondown' : 'utility:chevronright';
    }

    handleViewChange(event) {
        this.viewMode = event.currentTarget.dataset.view;
    }

    handleFilterChange(event) {
        this.filterMode = event.detail.value;

        // Auto-expand relevant sections based on filter
        if (this.filterMode === 'dependenton') {
            this.showUpstream = true;
            this.showDownstream = false;
        } else if (this.filterMode === 'dependentat') {
            this.showUpstream = false;
            this.showDownstream = true;
        } else {
            this.showUpstream = true;
            this.showDownstream = true;
        }
    }

    handleToggleSection(event) {
        const section = event.currentTarget.dataset.section;
        if (section === 'upstream') {
            this.showUpstream = !this.showUpstream;
        } else if (section === 'downstream') {
            this.showDownstream = !this.showDownstream;
        } else if (section === 'impact') {
            this.showImpactSummary = !this.showImpactSummary;
        }
    }

    handleAddDependency(event) {
        this.relationshipDirection = event.currentTarget.dataset.direction;
        this.showModal = true;
        this.searchTerm = '';
        this.searchResults = [];
        this.selectedAssetId = null;
        this.selectedAssetName = '';
    }

    handleCloseModal() {
        this.showModal = false;
        this.searchTerm = '';
        this.searchResults = [];
        this.selectedAssetId = null;
        this.selectedAssetName = '';
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        clearTimeout(this._searchDebounceTimer);
        if (this.searchTerm.length >= 2) {
            this._searchDebounceTimer = setTimeout(() => {
                this.performSearch();
            }, SEARCH_DEBOUNCE_MS);
        } else {
            this.searchResults = [];
        }
    }

    performSearch() {
        searchAssets({ searchTerm: this.searchTerm, excludeAssetId: this.recordId })
            .then(results => {
                this.searchResults = results;
            })
            .catch(error => {
                this.showError(error);
            });
    }

    handleAssetSelect(event) {
        this.selectedAssetId = event.currentTarget.dataset.assetId;
        this.selectedAssetName = event.currentTarget.dataset.assetName;
    }

    handleDependencyTypeChange(event) {
        this.dependencyType = event.detail.value;
    }

    handleImpactLevelChange(event) {
        this.impactLevel = event.detail.value;
    }

    handleSaveDependency() {
        if (!this.selectedAssetId) {
            this.showToast('Error', 'Please select an asset', 'error');
            return;
        }

        this.isCreating = true;

        const sourceAssetId = this.relationshipDirection === 'downstream' ? this.recordId : this.selectedAssetId;
        const dependentAssetId = this.relationshipDirection === 'downstream' ? this.selectedAssetId : this.recordId;

        createDependency({
            sourceAssetId: sourceAssetId,
            dependentAssetId: dependentAssetId,
            dependencyType: this.dependencyType,
            impactLevel: this.impactLevel
        })
        .then(() => {
            this.showToast('Success', 'Dependency created successfully', 'success');
            this.handleCloseModal();
            return refreshApex(this.wiredDependenciesResult);
        })
        .catch(error => {
            this.showError(error);
        })
        .finally(() => {
            this.isCreating = false;
        });
    }

    _pendingDeleteId;
    showDeleteConfirm = false;

    handleDeleteDependency(event) {
        this._pendingDeleteId = event.detail.dependencyId;
        this.showDeleteConfirm = true;
    }

    handleCancelDelete() {
        this._pendingDeleteId = null;
        this.showDeleteConfirm = false;
    }

    handleConfirmDelete() {
        this.showDeleteConfirm = false;
        deleteDependency({ dependencyId: this._pendingDeleteId })
            .then(() => {
                this.showToast('Success', 'Dependency deleted successfully', 'success');
                this._pendingDeleteId = null;
                return refreshApex(this.wiredDependenciesResult);
            })
            .catch(error => {
                this._pendingDeleteId = null;
                this.showError(error);
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }

    showError(error) {
        let message = 'Unknown error';
        if (Array.isArray(error.body)) {
            message = error.body.map(e => e.message).join(', ');
        } else if (typeof error.body?.message === 'string') {
            message = error.body.message;
        } else if (typeof error.message === 'string') {
            message = error.message;
        }

        this.showToast('Error', message, 'error');
    }
}
