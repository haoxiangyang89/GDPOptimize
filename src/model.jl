# This is the script to create the stage-wise optimization problems
# single stage forward pass problem, single stage backward Lagrangian relaxation problem
# terminal stage forward pass problem and terminal stage backward LR problem
function createIni(flightD,costD)
    # set up the first stage decision variable
    mp = Model(solver = GurobiSolver());

end

function createSingle(flightD,costD,D,L,Y,Z,E,EZ,H)
end

function createTerm(flightD,costD,D,L,Y,Z,E,EZ,H)
end

function lrSingle()
end

function lrTerm()
end
