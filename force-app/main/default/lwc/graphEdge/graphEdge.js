import { LightningElement, api } from 'lwc';

export default class GraphEdge extends LightningElement {
    @api edge;
    @api nodes;
    @api lens;

    get sourceNode() {
        return this.nodes?.find(n => n.id === this.edge.source);
    }

    get targetNode() {
        return this.nodes?.find(n => n.id === this.edge.target);
    }

    get edgePath() {
        if (!this.sourceNode || !this.targetNode) return '';

        const x1 = this.sourceNode.x || 0;
        const y1 = this.sourceNode.y || 0;
        const x2 = this.targetNode.x || 0;
        const y2 = this.targetNode.y || 0;

        // Calculate angle for node offset
        const angle = Math.atan2(y2 - y1, x2 - x1);
        const nodeRadius = 30;

        // Adjust start/end points to node edge
        const startX = x1 + Math.cos(angle) * nodeRadius;
        const startY = y1 + Math.sin(angle) * nodeRadius;
        const endX = x2 - Math.cos(angle) * nodeRadius;
        const endY = y2 - Math.sin(angle) * nodeRadius;

        return `M ${startX},${startY} L ${endX},${endY}`;
    }

    get edgeColor() {
        const category = this.edge.category?.toLowerCase();
        if (!category) return '#6b7280';

        const colorMap = {
            'power': '#ef4444',
            'network': '#3b82f6',
            'cooling': '#06b6d4',
            'data': '#8b5cf6',
            'structural': '#78350f',
            'safety': '#f59e0b',
            'contract': '#ec4899',
            'maintenance': '#10b981'
        };

        return colorMap[category] || '#6b7280';
    }

    get edgeWidth() {
        const strength = this.edge.strength?.toLowerCase();
        if (strength?.includes('hard')) return 4;
        if (strength?.includes('degraded')) return 2;
        return 1;
    }

    get edgeStyle() {
        const style = this.edge.style?.toLowerCase();
        if (style === 'logical') return '5,5';
        if (style === 'inferred') return '2,2';
        return '0';
    }

    get markerEnd() {
        const category = this.edge.category?.toLowerCase();
        if (category === 'power') return 'url(#arrowhead-power)';
        if (category === 'network') return 'url(#arrowhead-network)';
        if (category === 'cooling') return 'url(#arrowhead-cooling)';
        return 'url(#arrowhead)';
    }

    get labelPosition() {
        if (!this.sourceNode || !this.targetNode) return { x: 0, y: 0 };

        const x1 = this.sourceNode.x || 0;
        const y1 = this.sourceNode.y || 0;
        const x2 = this.targetNode.x || 0;
        const y2 = this.targetNode.y || 0;

        return {
            x: (x1 + x2) / 2,
            y: (y1 + y2) / 2
        };
    }
}
