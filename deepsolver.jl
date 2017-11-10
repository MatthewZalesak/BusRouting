# deepsolver.jl

# solver.jl

using JuMP
using Gurobi

include("pathfinding.jl")
include("linefinding.jl")

#= This type and the following solver run the optimization step. =#

type Solver
  arcs::Array{ConstraintRef}
  arc_lookup::Dict{Arc,Int64}
  demand::Array{ConstraintRef}
  demand_lookup::Dict{Tuple{Node,Int64},Int64}
  f::Array{Variable}
  m::Model
  y::Array{Variable}
  
  
  function Solver(prob::Problem)
    m = Model(solver=GurobiSolver(Presolve=0, OutputFlag=0))
    
    if prob.param.integer_y
      @variable(m, y[1:length(prob.comp.paths)] >= 0, Int)
    else
      @variable(m, y[1:length(prob.comp.paths)] >= 0)
    end
    if prob.param.integer_f
      @variable(m, f[1:length(prob.comp.lines)] >= 0, Int)
    else
      @variable(m, f[1:length(prob.comp.lines)] >= 0)
    end
    
    demand_lookup = Dict{Tuple{Node,Int64},Int64}()
    @constraintref demand[1:length(prob.data.demands)]
    for (i, (key, value)) in enumerate(prob.data.demands)
      paths = prob.comp.ST[key]
      demand[i] = @constraint(m, sum(y[paths]) >= value)
      demand_lookup[key] = i
    end
    
    arc_lookup = Dict{Arc,Int64}()
    @constraintref arcs[1:length(prob.data.arcs)]
    for (i, a) in enumerate(values(prob.data.arcs))
      paths = prob.comp.lookup_paths[a]
      lines = prob.comp.lookup_lines[a]
      arcs[i] = @constraint(m, sum(y[paths]) -
          prob.param.bus_capacity * sum(f[lines]) <= 0)
      arc_lookup[a] = i
    end
    
    @objective(m, :Min, sum(prob.comp.pathcosts.*y) + sum(prob.comp.linecosts.*f))
    
    return new(arcs, arc_lookup, demand, demand_lookup, f, m, y)
  end
end

function init(s::Solver)
  if length(prob.comp.paths) == length(s.y) && length(prob.comp.lines) == length(s.f)
    if ( solve(s.m) != :Optimal )
      throw(ErrorException("No optimal solution found to this LP."))
    end
  end
end

function resolve(prob::Problem, s::Solver)
  for i in length(s.y) + 1:length(prob.comp.paths)
    path = prob.comp.paths[i]
    o, d = od(path.route)
    st_values = zeros(length(s.demand))
    st_values[s.demand_lookup[(o, d.id)]] = 1.0
    arc_values = zeros(1:length(s.arcs))
    for a in path.route.buses
      arc_values[s.arc_lookup[a]] = 1.0
    end
    @variable(s.m, y_temp >= 0, objective = prob.comp.pathcosts[i],
        inconstraints = vcat(s.demand, s.arcs),
        coefficients = vcat(st_values, arc_values))
    
    push!(s.y, y_temp)
    if ( solve(s.m) != :Optimal )
      throw(ErrorException("No optimal solution found to this LP."))
    end
  end
  
  for j in length(s.f) + 1:length(prob.comp.lines)
    line = prob.comp.lines[j]
    arc_values = zeros(length(s.arcs))
    for a in line.line
      arc_values[s.arc_lookup[a]] = -prob.param.bus_capacity
    end
    @variable(s.m, f_temp >= 0, objective = prob.comp.linecosts[j],
        inconstraints = s.arcs,
        coefficients = arc_values)
    push!(s.f, f_temp)
    if ( solve(s.m) != :Optimal)
      throw(ErrorException("No optimal solution found to this LP."))
    end
  end
  
  prob.sol.y = getvalue(s.y)
  prob.sol.f = getvalue(s.f)
  prob.sol.dualdemand = getdual(s.demand)
  prob.sol.dualarc = -getdual(s.arcs)
  for (x, a) in zip(prob.sol.dualarc, values(prob.data.arcs))
    a.data.dualvalue = x
  end
  prob.sol.objective = s.m.objVal
end

#= These functions run the column generation process. =#

function autosolvedeep(prob::Problem, pf::PathFinder, lfs::Array{LineFinder})
  if prob.param.integer_f || prob.param.integer_y
    return autosolve(prob)
  end
  
  s = Solver(prob)
  init(s)
  
  i = 100000 # max_iter
  while (i -= 1) >= 0
    @time resolve(prob, s)
    println("Iteration: ", i, "\t(with objective ", prob.sol.objective, ".)")
    
    if rand() > prob.param.search_weighting # Control order new vars added in.
      sp = search_path(pf)
      if sp
        continue
      end
      sl = search_line(lfs)
      if sl
        continue
      end
    else
      sl = search_line(lfs)
      if sl
        continue
      end
      sp = search_path(pf)
      if sp
        continue
      end
    end
    
    state_solution(prob)
    return
  end
  throw(ErrorException("Solver did not converge in max iterations. - MZ"))
end

function autosolvedeep(prob::Problem)
  if prob.param.integer_f || prob.param.integer_y
    return autosolve(prob)
  end
  
  pathfinder = PathFinder(prob)
  linefinders = [LineFinder(prob, c) for c in prob.param.cycletimes]
  autosolvedeep(prob, pathfinder, linefinders)
  
  return pathfinder, linefinders
end
