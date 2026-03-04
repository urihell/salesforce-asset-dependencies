import { LightningElement, api } from 'lwc';

export default class AssetTreeView extends LightningElement {
    @api rootAsset;
    @api upstreamDependencies;
    @api showUpstream;
    @api showDownstream;
    @api showCurrent;

    get hasUpstream() {
        const shouldShow = this.showUpstream !== false; // Show by default
        return shouldShow && this.upstreamDependencies && this.upstreamDependencies.length > 0;
    }

    get hasDownstream() {
        const shouldShow = this.showDownstream !== false; // Show by default
        return shouldShow && this.rootAsset?.children && this.rootAsset.children.length > 0;
    }

    get shouldShowCurrent() {
        return this.showCurrent !== false; // Show by default
    }

    handleDeleteDependency(event) {
        // Bubble up the event to parent
        this.dispatchEvent(new CustomEvent('deletedependency', {
            detail: event.detail,
            bubbles: true,
            composed: true
        }));
    }
}
