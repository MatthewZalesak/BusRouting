# solver.jl

using JuMP
using Gurobi

include("pathfinding.jl")
include("linefinding.jl")


function runlp(prob::Problem)
  m = Model(solver = GurobiSolver(Presolve=0, OutputFlag=0))
  
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
  
  count = 0
  arcref = Array{Int64}(length(prob.data.arcs))
  for (i, a) in enumerate(values(prob.data.arcs))
    paths = prob.comp.lookup_paths[a]
    lines = prob.comp.lookup_lines[a]
    if true # length(paths) > 0
      @constraint(m, sum(y[paths]) - prob.param.bus_capacity * sum(f[lines]) <= 0)
      count += 1
      arcref[i] = count
    else
      arcref[i] = 0
    end
  end
  
  for (key, value) in prob.data.demands
    paths = prob.comp.ST[key]
    @constraint(m, sum(y[paths]) >= value)
  end
  
  @objective(m, :Min, sum(prob.comp.pathcosts.*y) + sum(prob.comp.linecosts.*f))
  
  if ( solve(m) != :Optimal )
    throw(ErrorException("No Optimal Solution found to this LP."))
  end
  
  # Write solution.
  prob.sol.y = getvalue(y)
  prob.sol.f = getvalue(f)
  prob.sol.dualdemand = m.linconstrDuals[count + 1 : end]
  prob.sol.dualarc = Array{Float64}(length(prob.data.arcs))
  for (i, a) in enumerate(values(prob.data.arcs))
    prob.sol.dualarc[i] = arcref[i] == 0 ? 0 : -m.linconstrDuals[arcref[i]]
    a.data.dualvalue = prob.sol.dualarc[i]
  end
  prob.sol.objective = m.objVal
  
  return m
end



function autosolve(prob::Problem, pf::PathFinder, lfs::Array{LineFinder})
  if prob.param.integer_f || prob.param.integer_y
    runlp(prob)
    state_solution(prob)
    return
  end
  
  i = 100000 # max_iter
  while (i -= 1) >= 0
    runlp(prob)
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

function autosolve(prob::Problem)
  if prob.param.integer_f || prob.param.integer_y
    runlp(prob)
    state_solution(prob)
    return
  end
  
  pathfinder = PathFinder(prob)   # These two objects reduce memory allocation
  linefinders = LineFinder[]      # each iteration by preallocating what is needed.
  for cycletime in prob.param.cycletimes
    linefinder = LineFinder(prob, cycletime)
    push!(linefinders, linefinder)
  end
  
  autosolve(prob, pathfinder, linefinders)
  return pathfinder, linefinders
end
