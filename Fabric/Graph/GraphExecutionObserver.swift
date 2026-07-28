//
//  GraphExecutionObserver.swift
//  Fabric
//

import Foundation

/// Receives synchronous notification after a graph execution pass succeeds.
///
/// The renderer keeps observers weakly. Implementations should copy any
/// immutable state they need before returning and move expensive work off the
/// execution thread.
public protocol GraphExecutionObserver: AnyObject
{
    func graphRenderer(
        _ renderer: GraphRenderer,
        didCompleteExecutionOf graph: Graph,
        executionInfo: GraphExecutionInfo,
        executedNodes: [Node]
    )
}

final class WeakGraphExecutionObserver
{
    weak var observer: (any GraphExecutionObserver)?

    init(observer: any GraphExecutionObserver)
    {
        self.observer = observer
    }
}
