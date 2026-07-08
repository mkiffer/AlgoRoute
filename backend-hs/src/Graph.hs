type NodeID = Int64

data Coord = Coord 
    { 
      lat :: Double, 
      lon :: Double
    }
data Node = Node 
    { 
      nodeId :: NodeID, 
      coord :: Coord
    }
data Edge = Edge 
    {
      from, to :: NodeID, 
      weight :: Double, 
      wayId :: Int64 
    }
data Network = Network
    {
      nodes :: Map NodeID Node,
      adjacencyList :: Map NodeID [Edge]
    }
