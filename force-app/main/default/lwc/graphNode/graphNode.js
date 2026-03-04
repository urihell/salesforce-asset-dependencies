import { LightningElement, api } from 'lwc';

export default class GraphNode extends LightningElement {
    @api node;
    @api lens;

    get nodeClass() {
        let classes = ['graph-node'];
        if (this.node.isFocus) classes.push('focus-node');
        if (this.node.impactLevel === 'direct') classes.push('impact-direct');
        if (this.node.impactLevel === 'indirect') classes.push('impact-indirect');
        return classes.join(' ');
    }

    get nodeX() {
        return this.node.x || 0;
    }

    get nodeY() {
        return this.node.y || 0;
    }

    get iconName() {
        const typeMap = {
            'network': 'utility:network',
            'device': 'utility:product',
            'server': 'utility:database',
            'rack': 'utility:layers',
            'facility': 'utility:building',
            'vehicle': 'utility:truck',
            'hvac': 'utility:temperature'
        };
        return typeMap[this.node.nodeType] || 'standard:asset_object';
    }

    get statusClass() {
        const status = this.node.status?.toLowerCase();
        if (!status) return 'status-unknown';
        if (status.includes('active') || status.includes('installed') || status.includes('service')) {
            return 'status-active';
        }
        if (status.includes('degraded')) return 'status-degraded';
        if (status.includes('down') || status.includes('defective')) return 'status-down';
        return 'status-unknown';
    }

    get hasSignals() {
        return this.node.signals &&
               (this.node.signals.openWorkOrders > 0 ||
                this.node.signals.openCases > 0 ||
                this.node.signals.activeAlerts > 0);
    }

    get signalCount() {
        if (!this.node.signals) return 0;
        return this.node.signals.openWorkOrders +
               this.node.signals.openCases +
               this.node.signals.activeAlerts;
    }

    get nodeTransform() {
        return `translate(${this.nodeX}, ${this.nodeY})`;
    }
}
