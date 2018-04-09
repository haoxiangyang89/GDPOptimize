# define the capacity prediction parameters
type capData
  scenList :: Array{Any,1}
  cap :: Dict{Any,Any}
  prob :: Dict{Any,Any}
end

# define the flight schedule parameters
type fsData
  S1 :: Array{Any,1}
  S2 :: Array{Any,1}
  S3 :: Array{Any,1}
  arrInfo :: Dict{Any,Any}
  deptInfo :: Dict{Any,Any}
end

type faData
  ID :: String
  LC :: Int64
  τ :: Int64
  S :: Int64
end

type fdData
  ID :: String
  TS :: Int64
end

# define the cost parameters
type costData
  gc :: Dict{Any,Any}
  ac :: Float64
  zc :: Float64
  tc :: Dict{Any,Any}
  r :: Float64
end

# define the data type to store the cuts
type lCuts
end

# define the data type to store the scenario path
type scenPath
  ca :: Int64
  cd :: Int64
  ct :: Int64
end

# define the type of variable that stores previous solutions
type solType
  HX :: Dict{Any,Any}
  HY :: Dict{Any,Any}
  HZ :: Dict{Any,Any}
  HE :: Dict{Any,Any}
  HEZ :: Dict{Any,Any}
end

type timeType
  hr :: Int64
  min :: Int64
end
