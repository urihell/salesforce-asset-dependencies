import { LightningElement } from 'lwc';

export default class GraphLegend extends LightningElement {
    isExpanded = true;
    _isCompact = false;
    _resizeObserver;

    connectedCallback() {
        this._resizeObserver = new ResizeObserver(entries => {
            for (const entry of entries) {
                const width = entry.contentRect.width;
                this._isCompact = width < 600;
                if (this._isCompact && this.isExpanded) {
                    this.isExpanded = false;
                }
            }
        });
    }

    renderedCallback() {
        const host = this.template.host?.parentElement;
        if (host && this._resizeObserver) {
            this._resizeObserver.observe(host);
        }
    }

    disconnectedCallback() {
        if (this._resizeObserver) {
            this._resizeObserver.disconnect();
        }
    }

    handleToggle() {
        this.isExpanded = !this.isExpanded;
    }

    get toggleIconName() {
        return this.isExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get legendContainerClass() {
        return this._isCompact
            ? 'legend-container legend-compact'
            : 'legend-container';
    }
}
