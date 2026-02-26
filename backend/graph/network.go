package graph

import "fmt"

type Network struct {
	Nodes         map[NodeID]Node
	AdjacencyList map[NodeID][]Edge
}

func NewNetwork() *Network {
	return &Network{
		Nodes:         make(map[NodeID]Node),
		AdjacencyList: make(map[NodeID][]Edge),
	}
}

func (n *Network) AddNode(node Node) {
	n.Nodes[node.ID] = node
	// Ensure key exists so Neighbours() never returns nil.
	if _, exists := n.AdjacencyList[node.ID]; !exists {
		n.AdjacencyList[node.ID] = nil
	}
}

func (n *Network) AddEdge(edge Edge) error {
	if _, exists := n.Nodes[edge.From]; !exists {
		return fmt.Errorf("AddEdge: missing 'From' node %v ", edge.From)
	}
	if _, exists := n.Nodes[edge.To]; !exists {
		return fmt.Errorf("AddEdge: missing 'To' node %v ", edge.To)
	}
	if edge.Weight < 0 {
		return fmt.Errorf("AddEdge: negative edge weight %v ", edge.Weight)
	}

	n.AdjacencyList[edge.From] = append(n.AdjacencyList[edge.From], edge)
	return nil
}

func (n *Network) Neighbours(nodeID NodeID) []Edge {
	return n.AdjacencyList[nodeID]
}
