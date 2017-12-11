# reports.jl


#= Special functions for visualizing components of solutions. =#

function state_solution(prob::Problem)
  # Display useful information to the user.
  num_fractional_y = 0
  largest_den = 1
  #for (i, y) in enumerate(prob.sol.y)
  #  if round(y, 10) % 1.0 != 0
  #    num_fractional_y += 1
  #    largest_den = max(largest_den, Rational(round(y, 10)).den)
  #    warn("Fractional y variable: ", round(y, 6), " at ", i, "\t\t(cost ",
  #        round(prob.comp.pathcosts[i], 6), ")")
  #  end
  #end
  #num_fractional_f = 0
  #for (i, f) in enumerate(prob.sol.f)
  #  if prob.param.bus_capacity * round(f, 10) % 1 != 0
  #    num_fractional_f += 1
  #    warn("Fractional f variable: ", round(f, 6), " at ", i, "\t\t(cost ",
  #        round(prob.comp.linecosts[i], 6), ")")
  #  end
  #end
  
  #if num_fractional_y > 0
  #  print("NOTE: There were ", num_fractional_y, " fractional y variables.  ")
  #  println("Largest denominator: ", largest_den)
  #end
  #if num_fractional_f > 0
  #  println("NOTE: There were ", num_fractional_f, " fractional capacity f variables.")
  #end
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

function fractional_interferance(prob)
  anyoutput = false
  for a in values(prob.data.arcs)
    lines = prob.comp.lookup_lines[a]
    fractional = false
    for index in lines
      if round(prob.sol.f[index], 8) % 1.0 != 0
        fractional = true
        break
      end
    end
    
    if !fractional
      continue
    end
    if !anyoutput
      println("'*' indicates arcs between distinct locations.")
      anyoutput = true
    end
    star = a.o.id == a.d.id ? "" : "*"
    println("Found Blob: ", a.o, " ", a.d, " ", star)
    for index in lines
      value = prob.sol.f[index]
      if value > 0
        println("\t", round(value, 8), "\t", "ID ", index)
      end
    end
  end
end
