# reports.jl


#= Special functions for visualizing components of solutions. =#

function state_solution(prob::Problem)
  # Display useful information to the user.
  num_fractional = 0
  largest_den = 1
  for (i, y) in enumerate(prob.sol.y)
    if round(y, 10) % 1.0 != 0
      num_fractional += 1
      largest_den = max(largest_den, Rational(round(y, 10)).den)
      warn("Fractional y variable: ", round(y, 10), " at ", i, "\t\t(cost ",
          prob.comp.pathcosts[i], ")")
    end
  end
  if num_fractional > 0
    print("NOTE: There were ", num_fractional, " fractional y variables.  ")
    println("Largest denominator: ", largest_den)
  end
  num_fractional = 0
  for f in prob.sol.f
    if prob.param.bus_capacity * round(f, 10) % 1 != 0
      num_fractional += 1
    end
  end
  if num_fractional > 0
    println("NOTE: There were ", num_fractional, " fractional capacity f variables.")
  end
  obj = prob.sol.objective
  println("Complete!  The problem is solved with objective ", obj, "!")
  print("Number of paths: ", length(prob.comp.paths))
  println("  (", sum(prob.sol.y .> 0), " selected)")
  print("Number of lines: ", length(prob.comp.lines))
  println("  (", sum(prob.sol.f .> 0), " selected)")
end

function utilization_arcs(prob::Problem)
  num_arcs = length(prob.data.arcs)
  num_used = 0
  for a in values(prob.data.arcs)
    for p in prob.comp.lookup_paths[a]
      if prob.sol.y[p] > 0
        num_used += 1
        break
      end
    end
  end
  println("Paths utilize ", num_used, " of ", num_arcs, " arcs.")
  num_used = 0
  for a in values(prob.data.arcs)
    for l in prob.comp.lookup_lines[a]
      if prob.sol.f[l] > 0
        num_used += 1
        break
      end
    end
  end
  println("Lines utilize ", num_used, " of ", num_arcs, " arcs.")
end
