import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class AssetNode extends NavigationMixin(LightningElement) {
    @api asset;
    @api isRoot = false;
    @api isUpstream = false;
    @api isDownstream = false;

    get hasChildren() {
        return this.asset?.children && this.asset.children.length > 0;
    }

    get assetDisplayName() {
        return this.asset?.assetName || 'Unknown Asset';
    }

    get productDisplay() {
        return this.asset?.productName || '';
    }

    get serialDisplay() {
        return this.asset?.serialNumber ? `SN: ${this.asset.serialNumber}` : '';
    }

    get statusDisplay() {
        return this.asset?.status || '';
    }

    get dependencyTypeDisplay() {
        return this.asset?.dependencyType || '';
    }

    get impactLevelClass() {
        const level = this.asset?.impactLevel;
        if (level === 'Critical') return 'impact-badge critical';
        if (level === 'High') return 'impact-badge high';
        if (level === 'Medium') return 'impact-badge medium';
        if (level === 'Low') return 'impact-badge low';
        return 'impact-badge';
    }

    get nodeClass() {
        let baseClass = 'asset-node';
        if (this.isRoot) baseClass += ' root-node';
        if (this.isUpstream) baseClass += ' upstream-node';
        if (this.isDownstream) baseClass += ' downstream-node';
        return baseClass;
    }

    get statusClass() {
        const status = this.asset?.status;
        if (status === 'Installed' || status === 'Active') return 'status-badge active';
        if (status === 'Obsolete' || status === 'Defective') return 'status-badge inactive';
        return 'status-badge';
    }

    get showDependencyInfo() {
        return !this.isRoot && (this.asset?.dependencyType || this.asset?.impactLevel);
    }

    get canDelete() {
        return !this.isRoot && this.asset?.dependencyId;
    }

    handleAssetClick(event) {
        // Prevent navigation if clicking on delete button
        if (event.target.classList.contains('delete-button')) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.asset.assetId,
                objectApiName: 'Asset',
                actionName: 'view'
            }
        });
    }

    handleDelete(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('deletedependency', {
            detail: { dependencyId: this.asset.dependencyId },
            bubbles: true,
            composed: true
        }));
    }
}
