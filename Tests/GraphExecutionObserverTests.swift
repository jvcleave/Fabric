import Foundation
import Metal
import Satin
import Testing
@testable import Fabric

private final class ExecutionRecorder: GraphExecutionObserver
{
    struct Record
    {
        let graph: Graph
        let executionInfo: GraphExecutionInfo
        let executedNodes: [Node]
    }

    private(set) var records: [Record] = []

    func graphRenderer(
        _ renderer: GraphRenderer,
        didCompleteExecutionOf graph: Graph,
        executionInfo: GraphExecutionInfo,
        executedNodes: [Node]
    )
    {
        records.append(
            Record(
                graph: graph,
                executionInfo: executionInfo,
                executedNodes: executedNodes
            )
        )
    }
}

private final class WeakExecutionRecorderReference
{
    weak var recorder: ExecutionRecorder?

    init(recorder: ExecutionRecorder)
    {
        self.recorder = recorder
    }
}

private struct ObserverTestError: Error
{
}

private final class ThrowingObserverTestNode: Node
{
    override class var name: String { "Throwing Observer Test" }
    override class var nodeType: Node.NodeType { .Utility }
    override class var nodeExecutionMode: Node.ExecutionMode { .Consumer }
    override class var nodeTimeMode: Node.TimeMode { .None }
    override class var nodeDescription: String
    {
        "Throws to verify that failed graph passes do not notify observers."
    }

    override func execute(
        renderer: GraphRenderer,
        executionInfo: GraphExecutionInfo,
        renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer
    ) throws
    {
        throw ObserverTestError()
    }
}

@Suite("Graph Execution Observation")
struct GraphExecutionObserverTests
{
    @Test("A port exposes its current value without exposing mutation")
    func currentPortValue() throws
    {
        let port = NodePort<Float>(
            name: "Value",
            kind: .Outlet
        )

        #expect(port.currentPortValue() == nil)

        port.value = 3.25

        guard case .Float(let value) = port.currentPortValue()
        else
        {
            throw GraphExecutionTestFailure("Expected a boxed Float value")
        }

        #expect(value == 3.25)
    }

    @Test("Successful execution reports the graph, timing, and executed nodes")
    func successfulExecution() throws
    {
        guard let harness = GraphExecutionTestHarness()
        else
        {
            return
        }

        let graph = Graph(context: harness.context)
        let node = PassThroughNode<Float>(context: harness.context)
        node.input.value = 8
        graph.addNode(node)
        node.output.published = true
        graph.rebuildPublishedParameterGroup()

        let recorder = ExecutionRecorder()
        harness.renderer.addExecutionObserver(recorder)

        let executionInfo = harness.makeExecutionInfo(frameNumber: 17)
        try harness.execute(
            graph: graph,
            executionInfo: executionInfo
        )

        #expect(recorder.records.count == 1)
        #expect(recorder.records[0].graph === graph)
        #expect(recorder.records[0].executionInfo === executionInfo)
        #expect(recorder.records[0].executedNodes.contains { $0 === node })
    }

    @Test("The scheduled root draw reports completion")
    func scheduledRootExecution() throws
    {
        guard let harness = GraphExecutionTestHarness()
        else
        {
            return
        }

        let graph = harness.renderer.graph
        let node = PassThroughNode<Float>(context: harness.context)
        node.input.value = 5
        graph.addNode(node)
        node.output.published = true
        graph.rebuildPublishedParameterGroup()

        let recorder = ExecutionRecorder()
        harness.renderer.addExecutionObserver(recorder)
        try harness.renderer.update()

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture =
            try harness.makeTexture()

        guard let commandBuffer = harness.renderer.commandQueue
            .makeCommandBuffer()
        else
        {
            throw GraphExecutionTestFailure(
                "Failed to create a command buffer"
            )
        }

        try harness.renderer.draw(
            renderPassDescriptor: renderPassDescriptor,
            commandBuffer: commandBuffer
        )

        #expect(recorder.records.count == 1)
        #expect(recorder.records[0].graph === graph)
        #expect(recorder.records[0].executedNodes.contains { $0 === node })
    }

    @Test("Removing an observer stops delivery")
    func observerRemoval() throws
    {
        guard let harness = GraphExecutionTestHarness()
        else
        {
            return
        }

        let graph = Graph(context: harness.context)
        let node = PassThroughNode<Float>(context: harness.context)
        graph.addNode(node)
        node.output.published = true
        graph.rebuildPublishedParameterGroup()

        let recorder = ExecutionRecorder()
        harness.renderer.addExecutionObserver(recorder)
        harness.renderer.removeExecutionObserver(recorder)

        try harness.execute(graph)

        #expect(recorder.records.isEmpty)
    }

    @Test("The renderer does not retain an observer")
    func weakObserverLifetime()
    {
        guard let harness = GraphExecutionTestHarness()
        else
        {
            return
        }

        var weakReference: WeakExecutionRecorderReference?

        do
        {
            let recorder = ExecutionRecorder()
            weakReference = WeakExecutionRecorderReference(recorder: recorder)
            harness.renderer.addExecutionObserver(recorder)
        }

        #expect(weakReference?.recorder == nil)
    }

    @Test("A failed execution does not report completion")
    func failedExecution() throws
    {
        guard let harness = GraphExecutionTestHarness()
        else
        {
            return
        }

        let graph = Graph(context: harness.context)
        graph.addNode(ThrowingObserverTestNode(context: harness.context))

        let recorder = ExecutionRecorder()
        harness.renderer.addExecutionObserver(recorder)

        do
        {
            try harness.execute(graph)
            Issue.record("Expected graph execution to throw")
        }
        catch is ObserverTestError
        {
        }

        #expect(recorder.records.isEmpty)
    }
}
