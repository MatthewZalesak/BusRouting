# linefinding.jl

# Try statement protects items that cannot be initialized more than once.
try
  linefinding_init
catch
  type DummyNodeWrapper
    n::Node
    distance::Float64
    caller::Union{Void, DummyNodeWrapper}
    children::Array{DummyNodeWrapper}
    
    function DummyNodeWrapper(n::Node)
      return new(n, -Inf, nothing, DummyNodeWrapper[])
    end
  end
end
linefinding_init = true

type DummyArc
  o::DummyNodeWrapper
  d::DummyNodeWrapper
  dualvalue::Float64
  arcs::Array{Arc}
end

type LineFinder
  cycletime::Int64
  dummy_arcs::Dict{Tuple{DummyNodeWrapper,DummyNodeWrapper},DummyArc}
  graph::Array{DummyNodeWrapper}
  lookup::Dict{Node,DummyNodeWrapper}
  prob::Problem
  
  function LineFinder(prob::Problem, cycletime::Int64)
    dummy_arcs = Dict{Tuple{DummyNodeWrapper,DummyNodeWrapper},DummyArc}()
    graph = Array{DummyNodeWrapper}(prob.param.terminal_count * (cycletime + 1))
    lookup = Dict{Node,DummyNodeWrapper}()
    maximum_time = prob.data.terminals[end].t
    @assert(cycletime + 1 <= maximum_time)
    
    for i = 1:length(graph) # Populate graph
      n = prob.data.terminals[i]
      dnw = DummyNodeWrapper(n)
      graph[i], lookup[n] = dnw, dnw
    end
    for dnw in graph
      for child in prob.data.arc_children[dnw.n]
        child.t <= cycletime + 1 && push!(dnw.children, lookup[child])
      end
    end
    
    for ((o, d), a) in prob.data.arcs # Populate dummy_arcs
      if d.t <= cycletime + 1
        o_wrapper, d_wrapper = lookup[o], lookup[d]
        dummy_arcs[(o_wrapper, d_wrapper)] = DummyArc(o_wrapper, d_wrapper,0, Arc[])
      end
    end
    for ((o, d), a) in prob.data.arcs
      ot = (o.t - 1) % cycletime + 1
      dt = (d.t - 1) % cycletime > 0 ? (d.t - 1) % cycletime + 1 : cycletime + 1
      (ot < dt && dt - ot == d.t - o.t) || continue
      o_short = graph[(ot - 1) * prob.param.terminal_count + o.id] # Uses that nodes
      d_short = graph[(dt - 1) * prob.param.terminal_count + d.id] # are sorted.
      push!(dummy_arcs[(o_short, d_short)].arcs, a)
      dummy_arcs[(o_short, d_short)].dualvalue += a.data.dualvalue
    end
    
    return new(cycletime, dummy_arcs, graph, lookup, prob)
  end
end

function update(lfs::Array{LineFinder})
  for lf in lfs
    for da in values(lf.dummy_arcs)
      da.dualvalue = 0
      for a in da.arcs
        da.dualvalue += a.data.dualvalue
      end
    end
  end
end

function cleanup(lf::LineFinder)
  for dnw in lf.graph
    dnw.caller = nothing
    dnw.distance = -Inf
  end
end

function bellmanford(lf::LineFinder, origin::Int64)
  lf.graph[origin].distance = 0
  for dnw in lf.graph
    for child in dnw.children
      distance = dnw.distance + 
          lf.prob.param.bus_capacity * lf.dummy_arcs[(dnw, child)].dualvalue -
          (lf.prob.param.permile_bus * lf.prob.data.distances[(dnw.n.id, child.n.id)] *
              length(lf.dummy_arcs[(dnw, child)].arcs))
      if distance > child.distance
        child.distance = distance
        child.caller = dnw
      end
    end
  end
  
  tail = lf.graph[length(lf.graph) - lf.prob.param.terminal_count + origin]
  @assert(tail.n.id == origin)
  len = tail.distance
  
  line = DummyArc[]
  while tail.caller != nothing
    parent = tail.caller
    push!(line, lf.dummy_arcs[(parent, tail)])
    tail = parent
  end
  reverse!(line)
  
  cleanup(lf)
  @assert(tail.n.id == origin)
  return line, len
end

function expand_line(lf::LineFinder, da::Array{DummyArc})
  line = Arc[]
  iteration = 1
  cont = true
  while cont
    for a in da
      iteration <= length(a.arcs) || (cont = false ; break)
      push!(line, a.arcs[iteration])
    end
    iteration += 1
  end
  
  cost = 0
  cost += lf.prob.param.bus_fixedcost
  for a in line
    cost += lf.prob.param.permile_bus * lf.prob.data.distances[(a.o.id, a.d.id)]
  end
  
  return Line(line, cost, lf.cycletime, 0)
end

function duplicate_check(lf::LineFinder, line::Line, len::Float64)
  for l in lf.prob.comp.lines
    if l.line == line.line && l != line
      throw(ErrorException("This line was a repeat." * string(len)))
    end
  end
end

function apply_line(lf::LineFinder, line::Line, len::Float64)
  line.index = length(lf.prob.comp.lines) + 1
  push!(lf.prob.comp.lines, line)
  
  for arc in line.line
    push!(lf.prob.comp.lookup_lines[arc], line.index)
  end
  push!(lf.prob.comp.linecosts, line.cost)
  
  duplicate_check(lf, line, len)
end

function search_line(lfs::Array{LineFinder})
  update(lfs)
  
  lines = Tuple{LineFinder,Array{DummyArc},Float64}[]
  for lf in lfs
    for origin in 1:lf.prob.param.terminal_count
      arcs, len = bellmanford(lf, origin)
      if len > lf.prob.param.bus_fixedcost + lf.prob.param.epsilon
        push!(lines, (lf, arcs, len))
        sort!(lines, by = x->x[3], rev=true)
        length(lines) > lf.prob.param.batch_line ? pop!(lines) : nothing
      end
    end
  end
  
  for (lf, dummyarcs, len) in lines
    line = expand_line(lf, dummyarcs)
    apply_line(lf, line, len)
  end
  
  println("Lines added: ", length(lines))
  return length(lines) > 0
end
