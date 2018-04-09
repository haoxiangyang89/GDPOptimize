function SDDP_main(T,startT,endT,capD,flightD,costD,ϵ = 0.01,M = 10,MM = 100,zα = 1.96)
    # the main process for SDDP, startT and endT are integers between 1 and T

    # initialize with the lower bound and the statistical upper bound
    lb = 0;
    sub = 9999999;
    lbList = [];
    ubList = [];
    iterNo = 0;
    # create the stagewise problems
    probSet = Dict();
    cutSet = Dict();
    solSet = Dict();
    for t in startT:endT
        # for each stage, create the forward path problems
        # distinguish the first stage, the terminal stage and all stages in between
        if t == 1
            probSet[t] = createIni(flightD,costD);
        elseif t != T
            probSet[t] = createSingle(flightD,costD);
        else
            probSet[t] = createTerm(flightD,costD);
        end
        cutSet[t] = [];
        solSet[t] = [];
    end

    while (sub - lb) >= lb*ϵ
        iterNo += 1;
        # sample the forward path and record the capacity information for each stage
        capInfo = sampleForward(startT,endT,capD);

        for t in startT:endT
            if t == startT
                # for the first stage, do not need to inherit the last stage solution
                probt = changeCap1(probSet[t],capInfo[t],cutSet[t]);
                ptStatus = solve(probt);
                # update the lower bound
                push!(lbList,getobjectivevalue(probt));
                if getobjectivevalue(probt) > lb
                    lb = getobjectivevalue(probt);
                end
                # obtain the solution!!!!!!!
                solSet[t] = obtainSol(probt);
            elseif t < endT
                # for each stage after the first stage, solve the forward path and generate solutions
                # feed in the previous stage solution!!!!!!, cuts and scenario capacity
                probt = changeCapt(probSet[t],capInfo[t],solSet[t-1],cutSet[t]);
                ptStatus = solve(probt);
                # obtain the solution!!!!!!!
                solSet[t] = obtainSol(probt);
            else t == endT
                probt = changeCapT(probSet[t],capInfo[t],solSet[t-1]);
                ptStatus = solve(probt);
                # obtain the solution!!!!!!!
                solSet[t] = obtainSol(probt);
            end
        end

        # update the upper bound for every M iterations
        ubTemp = getUB(MM,zα,probSet,capInfo,cutSet);
        push!(ubList,ubTemp);
        if ubTemp < sub
            sub = ubTemp;
        end

        # backward recursion starts here
        for t in (endT-1):-1:startT
            if t == endT - 1
                # solve the terminal stage problem to generate cuts and append to cutSet
                cutSet[t] = cutUpdateT(probSet[t+1],capInfo[t+1],solSet[t],cutSet[t]);
            else
                # solve the t-th stage problem to generate cuts and append to cutSet
                cutSet[t] = cutUpdatet(probSet[t+1],capInfo[t+1],cutSet[t+1],solSet[t],cutSet[t]);
            end
        end
    end

    return solSet[startT],cutSet;
end
