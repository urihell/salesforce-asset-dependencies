import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getGraphData from '@salesforce/apex/AssetGraphController.getGraphData';
import getBlastRadius from '@salesforce/apex/AssetGraphController.getBlastRadius';
import getCriticalPath from '@salesforce/apex/AssetGraphController.getCriticalPath';
import expandNode from '@salesforce/apex/AssetGraphController.expandNode';
import createDependency from '@salesforce/apex/AssetDependencyController.createDependency';
import deleteDependency from '@salesforce/apex/AssetDependencyController.deleteDependency';
import searchAssets from '@salesforce/apex/AssetDependencyController.searchAssets';
import previewDependencies from '@salesforce/apex/AssetDependencyController.previewDependencies';
import createDiscoveredDependencies from '@salesforce/apex/AssetDependencyController.createDiscoveredDependencies';
import searchAssetsForNav from '@salesforce/apex/AssetGraphController.searchAssetsForNav';
import getContainmentHierarchy from '@salesforce/apex/AssetGraphController.getContainmentHierarchy';

const SEARCH_DEBOUNCE_MS = 300;

const ARROW_SIZE = 10;

export default class AssetRelationshipGraph extends NavigationMixin(LightningElement) {
    @api recordId;

    graphData;
    selectedNode;
    selectedEdge;
    viewLens = 'normal';
    showLegend = true;
    showFilters = false;
    error;
    isLoading = true;

    zoomLevel = 1;
    panX = 0;
    panY = 0;
    maxHops = 1;

    relationshipTypeFilters = [];
    assetTypeFilters = [];
    statusFilters = [];
    criticalPathData = null;

    showCreateModal = false;
    searchTerm = '';
    searchResults = [];
    selectedAssetId = null;
    dependencyType = '';
    impactLevel = '';
    relationshipCategory = '';
    dependencyStrength = '';
    isCreating = false;
    isDiscovering = false;

    showDiscoveryModal = false;
    discoveredDependencies = [];
    discoverySkipped = 0;
    bulkDependencyType = '';
    bulkCategory = '';
    bulkStrength = '';
    bulkImpact = '';

    navSearchTerm = '';
    navSearchResults = [];
    showNavSearchResults = false;
    breadcrumbs = [];
    showMiniMap = false;

    selectedTab = 'overview';
    showTableView = false;

    enableClustering = false;
    clusterThreshold = 5;

    _searchDebounceTimer;
    _navSearchDebounceTimer;
    _nodeHalfW = 80; // default fallback, updated from DOM
    _nodeHalfH = 32;
    _hasMeasured = false;
    _isDragging = false;
    _dragStartX = 0;
    _dragStartY = 0;
    _panStartX = 0;
    _panStartY = 0;

    connectedCallback() {
        this.loadGraphData();
        this.loadBreadcrumbs();
    }

    renderedCallback() {
        if (!this._hasMeasured) {
            this._measureNodeSize();
        }
        this._updateBaseScale();
        if (this._needsCenter) {
            this._needsCenter = false;
            this._centerGraphInViewport();
        }
    }

    _baseScale = 1;

    _updateBaseScale() {
        const wrapper = this.template.querySelector('.canvas-wrapper');
        if (!wrapper) return;
        const wrapperWidth = wrapper.clientWidth;
        if (wrapperWidth > 0 && wrapperWidth < 1400) {
            this._baseScale = wrapperWidth / 1400;
        } else {
            this._baseScale = 1;
        }
    }

    /**
     * Measure one node-status element to get the real rendered size.
     * All nodes share the same CSS so one measurement suffices.
     */
    _measureNodeSize() {
        const el = this.template.querySelector('.node-status');
        if (!el) return;
        this._nodeHalfW = el.offsetWidth / 2;
        this._nodeHalfH = el.offsetHeight / 2;
        this._hasMeasured = true;
    }

    loadGraphData() {
        this.isLoading = true;
        this.error = null;

        getGraphData({ focusAssetId: this.recordId, maxHops: this.maxHops })
            .then(data => {
                if (data && data.nodes) {
                    // Create mutable copies of the data since Apex returns read-only objects
                    this.graphData = {
                        focusAssetId: data.focusAssetId,
                        nodes: data.nodes.map(node => ({
                            ...node,
                            signals: node.signals ? { ...node.signals } : null
                        })),
                        edges: data.edges.map(edge => ({ ...edge }))
                    };
                    this.processGraphLayout();
                    this._needsCenter = true;
                    this._hasMeasured = false; // re-measure after new nodes render
                    this.error = null;
                } else {
                    this.error = { message: 'No graph data returned' };
                }
                this.isLoading = false;
            })
            .catch(error => {
                console.error('Error loading graph data:', error);
                this.error = error;
                this.showError(error);
                this.isLoading = false;
                this.graphData = null;
            });
    }

    /**
     * Process graph layout using layered (Sugiyama-style) positioning.
     * 1. Assign each node a layer (column) via BFS from the focus node.
     *    - Upstream parents get negative layers, downstream children positive.
     * 2. Within each layer, order nodes using barycenter heuristic so that
     *    edges between adjacent layers do not cross.
     * 3. Position nodes on a grid: layer → x column, order → y row.
     */
    processGraphLayout() {
        if (!this.graphData || !this.graphData.nodes) return;

        const width = 1400;
        const height = 700;
        const centerX = width / 2;
        const centerY = height / 2;
        const colGap = 300;
        const rowGap = 120; // must exceed minDistance (100) to avoid overlap-push reordering

        const focusNode = this.graphData.nodes.find(n => n.isFocus);
        const focusId = focusNode?.id || this.recordId;

        // Build adjacency: source→[targets] and target→[sources]
        const children = new Map();  // source → targets (downstream)
        const parents = new Map();   // target → sources (upstream)
        this.graphData.edges.forEach(edge => {
            if (!children.has(edge.source)) children.set(edge.source, []);
            children.get(edge.source).push(edge.target);
            if (!parents.has(edge.target)) parents.set(edge.target, []);
            parents.get(edge.target).push(edge.source);
        });

        // --- Step 1: Assign layers via BFS ---
        const layerOf = new Map(); // nodeId → layer number
        layerOf.set(focusId, 0);

        // BFS downstream (positive layers)
        let queue = [focusId];
        while (queue.length > 0) {
            const next = [];
            for (const nid of queue) {
                const layer = layerOf.get(nid);
                for (const child of (children.get(nid) || [])) {
                    if (!layerOf.has(child)) {
                        layerOf.set(child, layer + 1);
                        next.push(child);
                    }
                }
            }
            queue = next;
        }

        // BFS upstream (negative layers)
        queue = [focusId];
        while (queue.length > 0) {
            const next = [];
            for (const nid of queue) {
                const layer = layerOf.get(nid);
                for (const parent of (parents.get(nid) || [])) {
                    if (!layerOf.has(parent)) {
                        layerOf.set(parent, layer - 1);
                        next.push(parent);
                    }
                }
            }
            queue = next;
        }

        // Assign any remaining unconnected nodes to layer 0
        for (const node of this.graphData.nodes) {
            if (!layerOf.has(node.id)) {
                layerOf.set(node.id, 0);
            }
        }

        // --- Step 2: Group nodes by layer ---
        const layers = new Map(); // layer → [nodeId, ...]
        for (const [nid, layer] of layerOf) {
            if (!layers.has(layer)) layers.set(layer, []);
            layers.get(layer).push(nid);
        }

        // Sort layer keys so we process left-to-right
        const sortedLayerKeys = [...layers.keys()].sort((a, b) => a - b);

        // --- Step 3: Barycenter ordering to minimize crossings ---
        // Start from focus layer outward. For each layer, order nodes by the
        // average y-position of their neighbours in the already-positioned
        // adjacent layer.
        const positionOf = new Map(); // nodeId → { order } within its layer

        // Build name lookup for stable tiebreaker sort
        const nameOf = new Map();
        for (const node of this.graphData.nodes) {
            nameOf.set(node.id, (node.name || '').toLowerCase());
        }

        // Stable sort: barycenter first, then alphabetical name as tiebreaker
        const stableSort = (arr) => {
            arr.sort((a, b) => {
                if (a.bc !== b.bc) return a.bc - b.bc;
                return (nameOf.get(a.id) || '').localeCompare(nameOf.get(b.id) || '');
            });
        };

        // Initial arbitrary order for focus layer
        const focusLayer = layers.get(0) || [];
        focusLayer.forEach((nid, i) => positionOf.set(nid, i));

        // Order layers to the right (positive) of focus
        for (const lk of sortedLayerKeys) {
            if (lk <= 0) continue;
            const nodesInLayer = layers.get(lk);
            const barycenters = nodesInLayer.map(nid => {
                const pars = (parents.get(nid) || []).filter(p => layerOf.get(p) === lk - 1);
                if (pars.length === 0) return { id: nid, bc: 0 };
                const avg = pars.reduce((sum, p) => sum + (positionOf.get(p) ?? 0), 0) / pars.length;
                return { id: nid, bc: avg };
            });
            stableSort(barycenters);
            barycenters.forEach((item, i) => positionOf.set(item.id, i));
            layers.set(lk, barycenters.map(b => b.id));
        }

        // Order layers to the left (negative) of focus
        for (let i = sortedLayerKeys.length - 1; i >= 0; i--) {
            const lk = sortedLayerKeys[i];
            if (lk >= 0) continue;
            const nodesInLayer = layers.get(lk);
            const barycenters = nodesInLayer.map(nid => {
                const chs = (children.get(nid) || []).filter(c => layerOf.get(c) === lk + 1);
                if (chs.length === 0) return { id: nid, bc: 0 };
                const avg = chs.reduce((sum, c) => sum + (positionOf.get(c) ?? 0), 0) / chs.length;
                return { id: nid, bc: avg };
            });
            stableSort(barycenters);
            barycenters.forEach((item, i) => positionOf.set(item.id, i));
            layers.set(lk, barycenters.map(b => b.id));
        }

        // --- Step 4: Assign x,y positions ---
        const nodePositions = new Map();
        for (const lk of sortedLayerKeys) {
            const nodesInLayer = layers.get(lk);
            const x = centerX + lk * colGap;
            const startY = centerY - ((nodesInLayer.length - 1) * rowGap) / 2;
            nodesInLayer.forEach((nid, idx) => {
                nodePositions.set(nid, { x, y: startY + idx * rowGap });
            });
        }

        // Apply positions
        let updatedNodes = this.graphData.nodes.map(node => {
            const pos = nodePositions.get(node.id);
            return pos
                ? { ...node, x: pos.x, y: pos.y }
                : { ...node, x: centerX, y: centerY };
        });

        updatedNodes = this.preventNodeOverlap(updatedNodes);

        this.graphData = {
            ...this.graphData,
            nodes: updatedNodes
        };
    }

    /**
     * Prevent node overlap using simple collision detection
     */
    preventNodeOverlap(nodes) {
        const minDistance = 100; // Must be less than rowGap (120) to preserve layer ordering
        const iterations = 5; // Number of iterations to resolve overlaps

        for (let iter = 0; iter < iterations; iter++) {
            let hasOverlap = false;

            for (let i = 0; i < nodes.length; i++) {
                for (let j = i + 1; j < nodes.length; j++) {
                    const node1 = nodes[i];
                    const node2 = nodes[j];

                    const dx = node2.x - node1.x;
                    const dy = node2.y - node1.y;
                    const distance = Math.sqrt(dx * dx + dy * dy);

                    if (distance < minDistance && distance > 0) {
                        hasOverlap = true;

                        // Calculate push force
                        const pushForce = (minDistance - distance) / 2;
                        const angle = Math.atan2(dy, dx);

                        // Don't move focus node
                        if (!node1.isFocus) {
                            node1.x -= Math.cos(angle) * pushForce;
                            node1.y -= Math.sin(angle) * pushForce;
                        }

                        if (!node2.isFocus) {
                            node2.x += Math.cos(angle) * pushForce;
                            node2.y += Math.sin(angle) * pushForce;
                        }
                    }
                }
            }

            if (!hasOverlap) break;
        }

        return nodes;
    }

    get lensOptions() {
        return [
            { label: 'Normal View', value: 'normal' },
            { label: 'Critical Path', value: 'criticalPath' },
            { label: 'Blast Radius', value: 'blastRadius' }
        ];
    }

    get hopOptions() {
        return [
            { label: '1 Hop', value: 1 },
            { label: '2 Hops', value: 2 },
            { label: '3 Hops', value: 3 },
            { label: 'All', value: 10 }
        ];
    }

    get relationshipTypeOptions() {
        return [
            { label: 'Power', value: 'Power' },
            { label: 'Network', value: 'Network' },
            { label: 'Cooling', value: 'Cooling' },
            { label: 'Data', value: 'Data' },
            { label: 'Structural', value: 'Structural' },
            { label: 'Safety', value: 'Safety' },
            { label: 'Contract', value: 'Contract' },
            { label: 'Maintenance', value: 'Maintenance' }
        ];
    }

    get statusFilterOptions() {
        return [
            { label: 'Active', value: 'active' },
            { label: 'Degraded', value: 'degraded' },
            { label: 'Down', value: 'down' },
            { label: 'With Open Work', value: 'openwork' }
        ];
    }

    get dependencyTypeOptions() {
        return [
            { label: 'Network Connection', value: 'Network Connection' },
            { label: 'Power Supply', value: 'Power Supply' },
            { label: 'Fiber Connection', value: 'Fiber Connection' },
            { label: 'Data Feed', value: 'Data Feed' },
            { label: 'Service Provider', value: 'Service Provider' },
            { label: 'Other', value: 'Other' }
        ];
    }

    get dependencyStrengthOptions() {
        return [
            { label: 'Hard Stop', value: 'Hard Stop' },
            { label: 'Degraded Service', value: 'Degraded Service' },
            { label: 'Soft Dependency', value: 'Soft Dependency' }
        ];
    }

    get hasGraphData() {
        return this.graphData && this.graphData.nodes && this.graphData.nodes.length > 0;
    }

    get nodes() {
        if (!this.graphData?.nodes) return [];

        try {
            return this.graphData.nodes
                .filter(node => this.passesNodeFilters(node))
                .map(node => {
                    return {
                        ...node,
                        positionStyle: `left: ${node.x || 0}px; top: ${node.y || 0}px;`,
                        hasSignals: this.hasNodeSignals(node),
                        signalCount: this.getNodeSignalCount(node),
                        hasWorkOrders: node.signals?.openWorkOrders > 0,
                        workOrderCount: node.signals?.openWorkOrders || 0,
                        hasCases: node.signals?.openCases > 0,
                        caseCount: node.signals?.openCases || 0,
                        hasAlerts: node.signals?.activeAlerts > 0,
                        alertCount: node.signals?.activeAlerts || 0,
                        statusClass: this.getNodeStatusClass(node),
                        iconName: this.getNodeIcon(node),
                        isOnCriticalPath: this.isNodeOnCriticalPath(node.id),
                        isExpandable: this.isNodeExpandable(node),
                        showDetails: this.shouldShowNodeDetails(),
                        showLabels: this.shouldShowNodeLabels()
                    };
                });
        } catch (error) {
            console.error('Error in nodes getter:', error);
            return [];
        }
    }

    shouldShowNodeDetails() {
        // Show full details when zoomed in (>150%)
        return this.zoomLevel > 1.5;
    }

    shouldShowNodeLabels() {
        // Show labels at medium zoom and above (>50%)
        return this.zoomLevel > 0.5;
    }

    get edges() {
        if (!this.graphData?.edges) return [];

        try {
            const hw = this._nodeHalfW;
            const hh = this._nodeHalfH;

            return this.graphData.edges
                .filter(edge => this.passesEdgeFilters(edge))
                .map(edge => {
                    const source = this.graphData.nodes.find(n => n.id === edge.source);
                    const target = this.graphData.nodes.find(n => n.id === edge.target);
                    if (!source || !target) return null;

                    const edgeData = this._computeEdge(
                        source.x || 0, source.y || 0,
                        target.x || 0, target.y || 0,
                        hw, hh, edge
                    );
                    return { ...edge, ...edgeData, isOnCriticalPath: this.isEdgeOnCriticalPath(edge.id) };
                }).filter(e => e !== null);
        } catch (error) {
            console.error('Error in edges getter:', error);
            return [];
        }
    }

    getEdgeColorForArrow(edge) {
        if (this.viewLens === 'criticalPath' && this.isEdgeOnCriticalPath(edge.id)) {
            return '#8b5cf6';
        }
        return this.getEdgeColor(edge.category);
    }

    get graphTransform() {
        return `translate(${this.panX}, ${this.panY}) scale(${this.zoomLevel})`;
    }

    get canvasStyle() {
        const scale = this._baseScale * this.zoomLevel;
        return `transform: translate(${this.panX}px, ${this.panY}px) scale(${scale});`;
    }

    get canvasWrapperStyle() {
        return `height: ${700 * this._baseScale}px;`;
    }

    get zoomClass() {
        if (this.zoomLevel <= 0.5) return 'low';
        if (this.zoomLevel <= 1.5) return 'medium';
        return 'high';
    }

    get canvasDataZoom() {
        return this.zoomClass;
    }

    get zoomPercentage() {
        return Math.round(this.zoomLevel * 100);
    }

    get nodeCount() {
        return this.graphData?.nodes?.length || 0;
    }

    get edgeCount() {
        return this.graphData?.edges?.length || 0;
    }

    handleLensChange(event) {
        this.viewLens = event.detail.value;
        if (this.viewLens === 'blastRadius') {
            this.calculateBlastRadius();
        } else if (this.viewLens === 'criticalPath') {
            this.calculateCriticalPath();
        } else {
            // Reset to normal view
            this.criticalPathData = null;
            if (this.graphData && this.graphData.nodes) {
                const updatedNodes = this.graphData.nodes.map(node => ({
                    ...node,
                    signals: node.signals ? { ...node.signals } : null,
                    impactLevel: 'none'
                }));
                this.graphData = {
                    ...this.graphData,
                    nodes: updatedNodes
                };
            }
        }
    }

    handleHopChange(event) {
        this.maxHops = event.detail.value;
        this.loadGraphData();
    }

    handleToggleLegend() {
        this.showLegend = !this.showLegend;
    }

    handleToggleFilters() {
        this.showFilters = !this.showFilters;
    }

    handleRelationshipTypeFilter(event) {
        this.relationshipTypeFilters = event.detail.value;
    }

    handleStatusFilter(event) {
        this.statusFilters = event.detail.value;
    }

    handleNodeClick(event) {
        const nodeId = event.currentTarget.dataset.nodeId;
        this.selectedNode = this.graphData.nodes.find(n => n.id === nodeId);
    }

    handleEdgeClick(event) {
        const edgeId = event.currentTarget.dataset.edgeId;
        this.selectedEdge = this.graphData.edges.find(e => e.id === edgeId);
    }

    handleZoomIn() {
        this.zoomLevel = Math.min(this.zoomLevel * 1.2, 3);
    }

    handleZoomOut() {
        this.zoomLevel = Math.max(this.zoomLevel / 1.2, 0.5);
    }

    handleResetView() {
        this.viewLens = 'normal';
        this._fitAndCenterGraph();
    }

    _centerGraphInViewport() {
        this._fitAndCenterGraph();
    }

    _fitAndCenterGraph() {
        const nodes = this.graphData?.nodes;
        if (!nodes || nodes.length === 0) {
            this.zoomLevel = 1;
            this.panX = 0;
            this.panY = 0;
            return;
        }

        // Node half-dimensions for bounding box padding
        const nodeW = 160;
        const nodeH = 64;

        // Compute bounding box of all nodes (including node dimensions)
        let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
        for (const node of nodes) {
            const nx = node.x || 0;
            const ny = node.y || 0;
            if (nx - nodeW / 2 < minX) minX = nx - nodeW / 2;
            if (nx + nodeW / 2 > maxX) maxX = nx + nodeW / 2;
            if (ny - nodeH / 2 < minY) minY = ny - nodeH / 2;
            if (ny + nodeH / 2 > maxY) maxY = ny + nodeH / 2;
        }

        const contentW = maxX - minX;
        const contentH = maxY - minY;
        const contentCenterX = (minX + maxX) / 2;
        const contentCenterY = (minY + maxY) / 2;

        // Measure the visible wrapper dimensions
        const wrapper = this.template.querySelector('.canvas-wrapper');
        const wrapperW = wrapper ? wrapper.clientWidth : 1400;
        const wrapperH = wrapper ? wrapper.clientHeight : 700 * this._baseScale;

        // Padding around the content (percentage of viewport)
        const padding = 0.15;
        const availW = wrapperW * (1 - padding * 2);
        const availH = wrapperH * (1 - padding * 2);

        // Compute zoom to fit content in viewport
        // The total scale = _baseScale * zoomLevel, so zoomLevel = desiredScale / _baseScale
        let fitZoom = 1;
        if (contentW > 0 && contentH > 0) {
            const scaleToFitW = availW / (contentW * this._baseScale);
            const scaleToFitH = availH / (contentH * this._baseScale);
            fitZoom = Math.min(scaleToFitW, scaleToFitH);
        }

        // Clamp zoom to reasonable bounds
        this.zoomLevel = Math.max(0.5, Math.min(fitZoom, 3));

        // Now center the content
        const scale = this._baseScale * this.zoomLevel;
        this.panX = (wrapperW / 2) - (contentCenterX * scale);
        this.panY = (wrapperH / 2) - (contentCenterY * scale);
    }

    handleCanvasMouseDown(event) {
        // Only drag with left mouse button, and not when clicking on nodes/edges
        if (event.button !== 0) return;
        this._isDragging = true;
        this._dragStartX = event.clientX;
        this._dragStartY = event.clientY;
        this._panStartX = this.panX;
        this._panStartY = this.panY;
    }

    handleCanvasMouseMove(event) {
        if (!this._isDragging) return;
        const dx = event.clientX - this._dragStartX;
        const dy = event.clientY - this._dragStartY;
        this.panX = this._panStartX + dx;
        this.panY = this._panStartY + dy;
    }

    handleCanvasMouseUp() {
        this._isDragging = false;
    }

    handleClosePanel() {
        this.selectedNode = null;
        this.selectedEdge = null;
    }

    get selectedEdgeSourceName() {
        if (!this.selectedEdge || !this.graphData?.nodes) return '';
        const sourceNode = this.graphData.nodes.find(n => n.id === this.selectedEdge.source);
        return sourceNode?.name || '';
    }

    get selectedEdgeTargetName() {
        if (!this.selectedEdge || !this.graphData?.nodes) return '';
        const targetNode = this.graphData.nodes.find(n => n.id === this.selectedEdge.target);
        return targetNode?.name || '';
    }

    showDeleteConfirm = false;

    handleDeleteDependency() {
        if (!this.selectedEdge || !this.selectedEdge.id) {
            this.showToast('Error', 'No dependency selected', 'error');
            return;
        }
        this.showDeleteConfirm = true;
    }

    handleCancelDelete() {
        this.showDeleteConfirm = false;
    }

    handleConfirmDelete() {
        this.showDeleteConfirm = false;
        deleteDependency({ dependencyId: this.selectedEdge.id })
            .then(() => {
                this.showToast('Success', 'Dependency deleted successfully', 'success');
                this.selectedEdge = null;
                this.loadGraphData();
            })
            .catch(error => {
                console.error('Error deleting dependency:', error);
                this.showError(error);
            });
    }

    handleOpenCreateModal() {
        this.showCreateModal = true;
        this.resetModalFields();
    }

    handleCloseCreateModal() {
        this.showCreateModal = false;
        this.resetModalFields();
    }

    handleStopPropagation(event) {
        event.stopPropagation();
    }

    resetModalFields() {
        this.searchTerm = '';
        this.searchResults = [];
        this.selectedAssetId = null;
        this.dependencyType = '';
        this.impactLevel = '';
        this.relationshipCategory = '';
        this.dependencyStrength = '';
        this.relationshipStyle = 'Physical';
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        clearTimeout(this._searchDebounceTimer);
        if (this.searchTerm && this.searchTerm.length >= 2) {
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
                this.searchResults = results.map(asset => ({
                    value: asset.assetId,
                    label: asset.assetName + (asset.serialNumber ? ' (' + asset.serialNumber + ')' : '')
                }));
            })
            .catch(error => {
                console.error('Error searching assets:', error);
                this.showError(error);
            });
    }

    handleAssetSelect(event) {
        this.selectedAssetId = event.detail.value;
    }

    handleDependencyTypeChange(event) {
        this.dependencyType = event.detail.value;
    }

    handleImpactLevelChange(event) {
        this.impactLevel = event.detail.value;
    }

    handleRelationshipCategoryChange(event) {
        this.relationshipCategory = event.detail.value;
    }

    handleDependencyStrengthChange(event) {
        this.dependencyStrength = event.detail.value;
    }

    handleRelationshipStyleChange(event) {
        this.relationshipStyle = event.detail.value;
    }

    get relationshipStyleOptions() {
        return [
            { label: 'Physical (Solid)', value: 'Physical' },
            { label: 'Logical (Dashed)', value: 'Logical' },
            { label: 'Inferred (Dotted)', value: 'Inferred' }
        ];
    }

    handleCreateDependency() {
        if (!this.selectedAssetId) {
            this.showToast('Error', 'Please select an asset', 'error');
            return;
        }

        this.isCreating = true;

        createDependency({
            sourceAssetId: this.recordId,
            dependentAssetId: this.selectedAssetId,
            dependencyType: this.dependencyType,
            impactLevel: this.impactLevel,
            relationshipCategory: this.relationshipCategory,
            dependencyStrength: this.dependencyStrength,
            relationshipStyle: this.relationshipStyle
        })
            .then(() => {
                this.showToast('Success', 'Dependency created successfully', 'success');
                this.handleCloseCreateModal();
                this.loadGraphData(); // Reload graph
            })
            .catch(error => {
                console.error('Error creating dependency:', error);
                this.showError(error);
            })
            .finally(() => {
                this.isCreating = false;
            });
    }

    handleDiscoverDependencies() {
        this.isDiscovering = true;
        previewDependencies({ assetId: this.recordId })
            .then(result => {
                this.discoveredDependencies = (result.candidates || []).map((c, idx) => ({
                    ...c,
                    selected: true,
                    index: idx
                }));
                this.discoverySkipped = result.skipped || 0;
                this.bulkDependencyType = '';
                this.bulkCategory = '';
                this.bulkStrength = '';
                this.bulkImpact = '';
                this.showDiscoveryModal = true;
            })
            .catch(error => {
                console.error('Error previewing dependencies:', error);
                this.showError(error);
            })
            .finally(() => {
                this.isDiscovering = false;
            });
    }

    get discoveryTotal() {
        return this.discoveredDependencies.length;
    }

    get discoverySelectedCount() {
        return this.discoveredDependencies.filter(d => d.selected).length;
    }

    get discoveryHasCandidates() {
        return this.discoveredDependencies.length > 0;
    }

    get isConfirmDisabled() {
        return this.discoverySelectedCount === 0;
    }

    handleToggleCandidate(event) {
        const idx = parseInt(event.target.dataset.index, 10);
        this.discoveredDependencies = this.discoveredDependencies.map((d, i) =>
            i === idx ? { ...d, selected: !d.selected } : d
        );
    }

    handleSelectAll() {
        this.discoveredDependencies = this.discoveredDependencies.map(d => ({ ...d, selected: true }));
    }

    handleDeselectAll() {
        this.discoveredDependencies = this.discoveredDependencies.map(d => ({ ...d, selected: false }));
    }

    handleBulkTypeChange(event) {
        this.bulkDependencyType = event.detail.value;
    }

    handleBulkCategoryChange(event) {
        this.bulkCategory = event.detail.value;
    }

    handleBulkStrengthChange(event) {
        this.bulkStrength = event.detail.value;
    }

    handleBulkImpactChange(event) {
        this.bulkImpact = event.detail.value;
    }

    handleApplyBulkAttributes() {
        this.discoveredDependencies = this.discoveredDependencies.map(d => {
            if (!d.selected) return d;
            return {
                ...d,
                dependencyType: this.bulkDependencyType || d.dependencyType,
                relationshipCategory: this.bulkCategory || d.relationshipCategory,
                dependencyStrength: this.bulkStrength || d.dependencyStrength,
                impactLevel: this.bulkImpact || d.impactLevel
            };
        });
        this.showToast('Attributes Applied', 'Bulk attributes applied to selected candidates.', 'success');
    }

    handleConfirmDiscovery() {
        const selected = this.discoveredDependencies.filter(d => d.selected);
        if (selected.length === 0) return;

        // Strip UI-only fields before sending to Apex
        const payload = selected.map(({ sourceAssetId, sourceAssetName, dependentAssetId, dependentAssetName,
            dependencyType, impactLevel, relationshipCategory, dependencyStrength, strategy }) => ({
            sourceAssetId, sourceAssetName, dependentAssetId, dependentAssetName,
            dependencyType, impactLevel, relationshipCategory, dependencyStrength, strategy
        }));

        this.isDiscovering = true;
        createDiscoveredDependencies({ candidatesJson: JSON.stringify(payload) })
            .then(count => {
                this.showToast('Discovery Complete',
                    `Created ${count} dependenc${count === 1 ? 'y' : 'ies'}.`, 'success');
                this.showDiscoveryModal = false;
                this.discoveredDependencies = [];
                this.loadGraphData();
            })
            .catch(error => {
                console.error('Error creating discovered dependencies:', error);
                this.showError(error);
            })
            .finally(() => {
                this.isDiscovering = false;
            });
    }

    handleCloseDiscoveryModal() {
        this.showDiscoveryModal = false;
        this.discoveredDependencies = [];
    }

    get confirmButtonLabel() {
        return `Create Selected (${this.discoverySelectedCount})`;
    }

    get impactLevelOptions() {
        return [
            { label: 'Critical', value: 'Critical' },
            { label: 'High', value: 'High' },
            { label: 'Medium', value: 'Medium' },
            { label: 'Low', value: 'Low' }
        ];
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

    // Search & Navigation Methods
    loadBreadcrumbs() {
        if (!this.recordId) return;

        getContainmentHierarchy({ assetId: this.recordId })
            .then(result => {
                if (result && result.length > 0) {
                    // Mark the last item
                    this.breadcrumbs = result.map((item, index) => ({
                        ...item,
                        isLast: index === result.length - 1
                    }));
                } else {
                    this.breadcrumbs = [];
                }
            })
            .catch(error => {
                console.error('Error loading breadcrumbs:', error);
                this.breadcrumbs = [];
            });
    }

    handleNavSearchChange(event) {
        this.navSearchTerm = event.target.value;
        clearTimeout(this._navSearchDebounceTimer);
        if (this.navSearchTerm && this.navSearchTerm.length >= 2) {
            this._navSearchDebounceTimer = setTimeout(() => {
                this.performNavSearch();
            }, SEARCH_DEBOUNCE_MS);
        } else {
            this.navSearchResults = [];
            this.showNavSearchResults = false;
        }
    }

    performNavSearch() {
        searchAssetsForNav({ searchTerm: this.navSearchTerm })
            .then(results => {
                this.navSearchResults = results;
                this.showNavSearchResults = results.length > 0;
            })
            .catch(error => {
                console.error('Error searching assets:', error);
                this.navSearchResults = [];
                this.showNavSearchResults = false;
            });
    }

    handleSearchResultClick(event) {
        const assetId = event.currentTarget.dataset.assetId;
        this.jumpToAsset(assetId);
    }

    handleBreadcrumbClick(event) {
        const assetId = event.currentTarget.dataset.assetId;
        this.jumpToAsset(assetId);
    }

    jumpToAsset(assetId) {
        // Navigate to the asset record page
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: assetId,
                objectApiName: 'Asset',
                actionName: 'view'
            }
        });
    }

    handleToggleMiniMap() {
        this.showMiniMap = !this.showMiniMap;
    }

    get hasBreadcrumbs() {
        return this.breadcrumbs && this.breadcrumbs.length > 0;
    }

    handleTabChange(event) {
        this.selectedTab = event.target.value;
    }

    handleToggleTableView() {
        this.showTableView = !this.showTableView;
    }

    get isOverviewTab() {
        return this.selectedTab === 'overview';
    }

    get isRelationshipsTab() {
        return this.selectedTab === 'relationships';
    }

    get isWorkTab() {
        return this.selectedTab === 'work';
    }

    get isHealthTab() {
        return this.selectedTab === 'health';
    }

    get relationshipsTableData() {
        if (!this.graphData?.edges) return [];

        return this.graphData.edges.map(edge => {
            const sourceNode = this.graphData.nodes.find(n => n.id === edge.source);
            const targetNode = this.graphData.nodes.find(n => n.id === edge.target);

            const direction = edge.source === this.recordId ? 'Downstream' : 'Upstream';
            const directionClass = direction === 'Downstream' ?
                'direction-badge direction-downstream' :
                'direction-badge direction-upstream';

            return {
                id: edge.id,
                relatedAssetName: direction === 'Downstream' ? targetNode?.name : sourceNode?.name,
                relatedAssetId: direction === 'Downstream' ? edge.target : edge.source,
                direction: direction,
                directionClass: directionClass,
                category: edge.category || '-',
                strength: edge.strength || '-',
                dependencyType: edge.dependencyType || '-',
                impactLevel: edge.impactLevel || '-',
                style: edge.style || '-'
            };
        });
    }

    get openWorkOrders() {
        return this.selectedNode?.signals?.openWorkOrders || 0;
    }

    get openCases() {
        return this.selectedNode?.signals?.openCases || 0;
    }

    get activeAlerts() {
        return this.selectedNode?.signals?.activeAlerts || 0;
    }

    get alertRecords() {
        return this.selectedNode?.signals?.alertRecords || [];
    }

    get hasAlertRecords() {
        return this.alertRecords.length > 0;
    }

    get workOrdersClass() {
        const count = this.openWorkOrders;
        return count > 0 ? 'metric-card alert' : 'metric-card';
    }

    get casesClass() {
        const count = this.openCases;
        return count > 0 ? 'metric-card alert' : 'metric-card';
    }

    get alertsClass() {
        const count = this.activeAlerts;
        return count > 0 ? 'metric-card alert' : 'metric-card';
    }

    handleExportRelationships() {
        if (!this.relationshipsTableData || this.relationshipsTableData.length === 0) {
            this.showToast('Warning', 'No relationships to export', 'warning');
            return;
        }

        // Create CSV content
        const headers = ['Related Asset', 'Direction', 'Category', 'Strength', 'Type', 'Impact'];
        const rows = this.relationshipsTableData.map(rel => [
            rel.relatedAssetName,
            rel.direction,
            rel.category,
            rel.strength,
            rel.dependencyType,
            rel.impactLevel
        ]);

        let csvContent = headers.join(',') + '\n';
        rows.forEach(row => {
            csvContent += row.map(cell => `"${cell}"`).join(',') + '\n';
        });

        // Create download link
        const blob = new Blob([csvContent], { type: 'text/csv' });
        const url = window.URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = `asset_relationships_${this.recordId}.csv`;
        link.click();
        window.URL.revokeObjectURL(url);

        this.showToast('Success', 'Relationships exported successfully', 'success');
    }

    handleToggleClustering() {
        this.enableClustering = !this.enableClustering;
        if (this.enableClustering) {
            this.applyClustering();
        } else {
            this.loadGraphData(); // Reload without clustering
        }
    }

    applyClustering() {
        if (!this.graphData || !this.graphData.nodes) return;

        // Group nodes by parent (container-based clustering)
        const clusters = new Map();

        this.graphData.nodes.forEach(node => {
            if (node.isFocus) return; // Don't cluster focus node

            const parentId = node.parentId || 'root';
            if (!clusters.has(parentId)) {
                clusters.set(parentId, []);
            }
            clusters.get(parentId).push(node);
        });

        // Identify clusters with enough nodes
        const clusterGroups = [];
        clusters.forEach((nodes, parentId) => {
            if (nodes.length >= this.clusterThreshold) {
                clusterGroups.push({
                    parentId: parentId,
                    nodes: nodes,
                    count: nodes.length
                });
            }
        });

        // For now, just mark clustered nodes
        // Full implementation would create cluster nodes
        const updatedNodes = this.graphData.nodes.map(node => ({
            ...node,
            isClustered: clusterGroups.some(cg =>
                cg.nodes.some(n => n.id === node.id)
            )
        }));

        this.graphData = {
            ...this.graphData,
            nodes: updatedNodes
        };

        if (clusterGroups.length > 0) {
            this.showToast('Info',
                `Found ${clusterGroups.length} cluster(s) with ${this.clusterThreshold}+ nodes`,
                'info');
        } else {
            this.showToast('Info',
                'No clusters found. Try lowering the threshold.',
                'info');
        }
    }

    get miniMapNodes() {
        if (!this.graphData?.nodes) return [];

        // Scale down nodes for mini-map (1400x700 -> 200x100)
        const scaleX = 200 / 1400;
        const scaleY = 100 / 700;

        return this.graphData.nodes.map(node => {
            const miniX = (node.x || 0) * scaleX;
            const miniY = (node.y || 0) * scaleY;

            return {
                ...node,
                miniX: miniX,
                miniY: miniY,
                miniPositionStyle: `left: ${miniX}px; top: ${miniY}px;`,
                miniNodeClass: node.isFocus ? 'mini-map-node focus' : 'mini-map-node'
            };
        });
    }

    /**
     * Viewport indicator on the mini-map.
     * Shows the currently visible portion of the canvas as a rectangle.
     * Mini-map canvas is 200x100 representing the 1400x700 graph canvas.
     */
    get miniMapViewportStyle() {
        const canvasW = 1400;
        const canvasH = 700;
        const miniW = 200;
        const miniH = 100;
        const scaleX = miniW / canvasW;
        const scaleY = miniH / canvasH;
        const z = this.zoomLevel;

        // Measure actual wrapper size if available, else use canvas dimensions
        const wrapper = this.template.querySelector('.canvas-wrapper');
        const wrapperW = wrapper ? wrapper.clientWidth : canvasW;
        const wrapperH = wrapper ? wrapper.clientHeight : canvasH;

        // Visible area in canvas coordinates
        const visW = wrapperW / z;
        const visH = wrapperH / z;

        // Visible center in canvas coords
        // transform-origin is center of canvas-inner; pan shifts the canvas
        const visCenterX = canvasW / 2 - this.panX / z;
        const visCenterY = canvasH / 2 - this.panY / z;

        const visLeft = visCenterX - visW / 2;
        const visTop = visCenterY - visH / 2;

        // Map to mini-map coords and clamp
        const left = Math.max(0, Math.min(miniW, visLeft * scaleX));
        const top = Math.max(0, Math.min(miniH, visTop * scaleY));
        const width = Math.max(4, Math.min(miniW - left, visW * scaleX));
        const height = Math.max(4, Math.min(miniH - top, visH * scaleY));

        return `left:${left}px;top:${top}px;width:${width}px;height:${height}px;`;
    }

    calculateBlastRadius() {
        if (!this.graphData || !this.graphData.nodes) return;

        getBlastRadius({ focusAssetId: this.recordId })
            .then(result => {
                if (!result) return;

                // Create new array with updated nodes to trigger reactivity
                const updatedNodes = this.graphData.nodes.map(node => {
                    const updatedNode = {
                        ...node,
                        signals: node.signals ? { ...node.signals } : null
                    };
                    if (result.directlyImpacted && result.directlyImpacted.includes(node.id)) {
                        updatedNode.impactLevel = 'direct';
                    } else if (result.indirectlyImpacted && result.indirectlyImpacted.includes(node.id)) {
                        updatedNode.impactLevel = 'indirect';
                    } else {
                        updatedNode.impactLevel = 'none';
                    }
                    return updatedNode;
                });

                this.graphData = {
                    ...this.graphData,
                    nodes: updatedNodes
                };
            })
            .catch(error => {
                console.error('Error calculating blast radius:', error);
                this.showError(error);
            });
    }

    calculateCriticalPath() {
        if (!this.graphData || !this.graphData.nodes) return;

        getCriticalPath({ focusAssetId: this.recordId })
            .then(result => {
                this.criticalPathData = result || { criticalNodes: [], criticalEdges: [] };

                // Reset impact levels by creating new nodes
                const updatedNodes = this.graphData.nodes.map(node => ({
                    ...node,
                    signals: node.signals ? { ...node.signals } : null,
                    impactLevel: 'none'
                }));

                this.graphData = {
                    ...this.graphData,
                    nodes: updatedNodes
                };
            })
            .catch(error => {
                console.error('Error calculating critical path:', error);
                this.showError(error);
                this.criticalPathData = { criticalNodes: [], criticalEdges: [] };
            });
    }

    // Filter helper methods
    passesNodeFilters(node) {
        if (!node) return false;

        // Status filter
        if (this.statusFilters && this.statusFilters.length > 0) {
            const status = node.status?.toLowerCase() || '';
            let passesStatus = false;

            for (const filter of this.statusFilters) {
                if (filter === 'active' && (status.includes('active') || status.includes('installed') || status.includes('service'))) {
                    passesStatus = true;
                }
                if (filter === 'degraded' && status.includes('degraded')) {
                    passesStatus = true;
                }
                if (filter === 'down' && (status.includes('down') || status.includes('defective'))) {
                    passesStatus = true;
                }
                if (filter === 'openwork' && this.hasNodeSignals(node)) {
                    passesStatus = true;
                }
            }

            if (!passesStatus) return false;
        }

        return true;
    }

    passesEdgeFilters(edge) {
        if (!edge) return false;

        // Relationship type filter
        if (this.relationshipTypeFilters && this.relationshipTypeFilters.length > 0) {
            if (!this.relationshipTypeFilters.includes(edge.category)) {
                return false;
            }
        }

        // Make sure both source and target nodes pass filters
        const sourceNode = this.graphData?.nodes?.find(n => n.id === edge.source);
        const targetNode = this.graphData?.nodes?.find(n => n.id === edge.target);

        if (!sourceNode || !targetNode) return false;

        return this.passesNodeFilters(sourceNode) && this.passesNodeFilters(targetNode);
    }

    isNodeOnCriticalPath(nodeId) {
        if (this.viewLens !== 'criticalPath' || !this.criticalPathData) return false;
        return this.criticalPathData.criticalNodes?.includes(nodeId) || false;
    }

    isEdgeOnCriticalPath(edgeId) {
        if (this.viewLens !== 'criticalPath' || !this.criticalPathData) return false;
        return this.criticalPathData.criticalEdges?.includes(edgeId) || false;
    }

    isNodeExpandable(node) {
        // Node is expandable if it's not the focus and has potential additional connections
        return node && !node.isFocus;
    }

    // Helper methods for node styling
    hasNodeSignals(node) {
        return node.signals &&
               (node.signals.openWorkOrders > 0 ||
                node.signals.openCases > 0 ||
                node.signals.activeAlerts > 0);
    }

    getNodeSignalCount(node) {
        if (!node.signals) return 0;
        return node.signals.openWorkOrders +
               node.signals.openCases +
               node.signals.activeAlerts;
    }

    getNodeStatusClass(node) {
        let classes = ['node-status'];
        const status = node.status?.toLowerCase();

        if (status?.includes('active') || status?.includes('installed') || status?.includes('service')) {
            classes.push('status-active');
        } else if (status?.includes('degraded')) {
            classes.push('status-degraded');
        } else if (status?.includes('down') || status?.includes('defective')) {
            classes.push('status-down');
        }

        if (node.isFocus) classes.push('focus-node');
        if (node.impactLevel === 'direct') classes.push('impact-direct');
        if (node.impactLevel === 'indirect') classes.push('impact-indirect');

        // Critical path styling
        if (this.viewLens === 'criticalPath') {
            if (this.isNodeOnCriticalPath(node.id)) {
                classes.push('critical-path-node');
            } else {
                classes.push('dimmed-node');
            }
        }

        return classes.join(' ');
    }

    getNodeIcon(node) {
        const typeMap = {
            'network': 'utility:broadcast',
            'device': 'utility:connected_apps',
            'server': 'utility:database',
            'rack': 'utility:layers',
            'facility': 'utility:building',
            'vehicle': 'utility:truck',
            'hvac': 'utility:temperature'
        };
        return typeMap[node.nodeType] || 'standard:asset_object';
    }

    /**
     * Compute edge path from source node center to target node center,
     * anchoring to the actual node borders using measured half-sizes.
     * sx,sy = source center; tx,ty = target center; hw,hh = half width/height.
     */
    _computeEdge(sx, sy, tx, ty, hw, hh, edge) {
        const isForward = tx >= sx;

        let startX, startY, endX, endY;

        if (isForward) {
            startX = sx + hw;
            startY = sy;
            endX = tx - hw;
            endY = ty;
        } else {
            startX = sx - hw;
            startY = sy;
            endX = tx + hw;
            endY = ty;
        }

        const hGap = Math.abs(endX - startX);
        const vGap = Math.abs(endY - startY);
        const cpOffset = Math.max(50, hGap * 0.45);

        let cp1X, cp1Y, cp2X, cp2Y;

        if (isForward) {
            cp1X = startX + cpOffset;
            cp1Y = startY;
            cp2X = endX - cpOffset;
            cp2Y = endY;
        } else {
            cp1X = startX - cpOffset;
            cp1Y = startY;
            cp2X = endX + cpOffset;
            cp2Y = endY;
        }

        // If nodes overlap horizontally, route the curve around them
        if (hGap < hw * 2 && vGap > hh * 2) {
            const loopOut = hw * 2 + 30;
            if (isForward) {
                cp1X = startX + loopOut;
                cp2X = endX - loopOut;
            } else {
                cp1X = startX - loopOut;
                cp2X = endX + loopOut;
            }
        }

        const pathData = `M ${startX} ${startY} C ${cp1X} ${cp1Y}, ${cp2X} ${cp2Y}, ${endX} ${endY}`;

        let color = this.getEdgeColor(edge.category);
        let width = this.getEdgeWidth(edge.strength);

        if (this.viewLens === 'criticalPath' && this.isEdgeOnCriticalPath(edge.id)) {
            color = '#8b5cf6';
            width = 4;
        }

        let opacity = 1;
        if (this.viewLens === 'criticalPath' && !this.isEdgeOnCriticalPath(edge.id)) {
            opacity = 0.2;
        }

        const arrowAngle = Math.atan2(endY - cp2Y, endX - cp2X) * (180 / Math.PI);
        const arrowPoints = `${-ARROW_SIZE},${-ARROW_SIZE / 2} 0,0 ${-ARROW_SIZE},${ARROW_SIZE / 2}`;
        const arrowTransform = `translate(${endX}, ${endY}) rotate(${arrowAngle})`;

        // Connection style: Physical=solid, Logical=dashed, Inferred=dotted
        const dashArray = this.getEdgeDashArray(edge.style);

        return {
            pathData,
            color,
            width,
            opacity,
            dashArray,
            arrowPoints,
            arrowTransform
        };
    }

    getEdgeColor(category) {
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
        return colorMap[category?.toLowerCase()] || '#6b7280';
    }

    getEdgeWidth(strength) {
        if (strength?.toLowerCase().includes('hard')) return 4;
        if (strength?.toLowerCase().includes('degraded')) return 2;
        return 1;
    }

    getEdgeDashArray(style) {
        const s = style?.toLowerCase() || '';
        if (s.includes('logical')) return '8,4';    // dashed
        if (s.includes('inferred')) return '2,4';   // dotted
        return 'none';                              // solid (Physical or default)
    }

    showError(error) {
        let message = 'Unknown error';
        if (error.body?.message) {
            message = error.body.message;
        } else if (error.message) {
            message = error.message;
        }

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message: message,
                variant: 'error'
            })
        );
    }
}