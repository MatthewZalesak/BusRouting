# solver.jl

using JuMP
using Gurobi

include("pathfinding.jl")
include("linefinding.jl")




function runlp(prob::Problem)
  m = Model(solver = GurobiSolver(Presolve=0, OutputFlag=0))
  
  @variable(m, y[1:length(prob.comp.paths)] >= 0)
  if prob.param.integer
    @variable(m, f[1:length(prob.comp.lines)] >= 0, Int)
  else
    @variable(m, f[1:length(prob.comp.lines)] >= 0)
  end
  
  count = 0
  arcref = Array{Int64}(length(prob.data.arcs))
  for (i, a) in enumerate(values(prob.data.arcs))
    paths = prob.comp.lookup_paths[a]
    lines = prob.comp.lookup_lines[a]
    if true #length(paths) > 0
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

function display_solver_results(prob::Problem)
  # Display useful information to the user.
  obj = prob.sol.objective
  println("Complete!  The problem is solved with objective ", obj, "!")
  print("Number of paths: ", length(prob.comp.paths))
  println("  (", sum(prob.sol.y .> 0), " selected)")
  print("Number of lines: ", length(prob.comp.lines))
  println("  (", sum(prob.sol.f .> 0), " selected)")
end

function autosolve(prob::Problem)
  i = 100000 # max_iter
  
  pathfinder = PathFinder(prob)   # These two objects reduce memory allocation
  linefinders = LineFinder[]      # each iteration by preallocating what is needed.
  for cycletime in prob.param.cycletimes
    linefinder = LineFinder(prob, cycletime)
    push!(linefinders, linefinder)
  end
  
  while (i -= 1) >= 0
    print("Iteration: ", i)
    runlp(prob) # @time runlp(prob)
    println("\t(with objective ", prob.sol.objective, ".)")
    
    if rand() > prob.param.search_weighting # Control order new vars added in.
      sp = search_path(pathfinder)
      if sp
        continue
      end
      sl = search_line(linefinders)
      if sl
        continue
      end
    else
      sl = search_line(linefinders)
      if sl
        continue
      end
      sp = search_path(pathfinder)
      if sp
        continue
      end
    end
    
    display_solver_results(prob)
    return nothing # linefinders
  end
  throw(ErrorException("Solver did not converge in max iterations. - MZ"))
end
  
  
  
  
