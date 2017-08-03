function generateCost(ct,tt,LC,S,TS,FSG1,FSG2,FSG3,FSG)
    g = Dict();
    a = Dict();
    c = Dict();
    tc = Dict();
    cz = Dict();
    r = Dict();
    # this is the functiono that generates all the costs
    for t in ct:tt
        for f in FSG
            r[f] = 40;
        end
        # generate the ground delay cost and airborne delay cost for planes that have not been cleared
        for f in FSG1
            if t > S[f]
                g[f,t] = 1.35^(t - S[f]);
            else
                g[f,t] = 0;
            end
            a[f] = 5;
            c[f,t] = 20;
        end
        # generate the ground delay cost and airborne delay cost for planes that have been cleared or exempted
        for f in FSG2
            if (t > S[f])&&(ct < S[f])
                g[f,t] = 1.35^(t - S[f]);
            else
                g[f,t] = 0;
            end
            a[f] = 5;
        end
        # generate the taxi-out cost for planes to depart
        for f in FSG3
            if (t > TS[f])
                tc[f,t] = 1.5^(t - TS[f]);
            else
                tc[f,t] = 0;
            end
            cz[f,t] = 20;
        end
    end
    return g,a,c,tc,cz,r
end
function initiMain(capAddress,capProbAdd,ArrAdd,DeptAdd,totalT,N)
    # this is the function that initiates the rolling horizon process

    # use 30 mins as a time period.
    # the planning span is defined by N.
    # the time horizon is defined by T.
    # the capacity profile is loaded from capAddress
    capacity_info_txt = readdlm(capAddress,',',header = false);
    capacity_prob_txt = readdlm(capProbAdd,',',header = false);
    # the first column contains the time period, the following columns are the possible capacity
    # transform the input raw data into two dictionary
    capDict = Dict();
    probDict = Dict();
    for t = 1:totalT
        capTemp = [];
        probTemp = [];
        for j in capacity_info_txt[t,2:length(capacity_info_txt[t,:])]
            #if (typeof(j) == Int)
            push!(capTemp,Int(j));
            #end
        end
        for j in capacity_prob_txt[t,2:length(capacity_prob_txt[t,:])]
            if (typeof(j) == Float64)||(typeof(j) == Int)
                push!(probTemp,j);
            end
        end
        capDict[t] = capTemp;
        probDict[t] = probTemp;
    end

    # read in the original arrival flight schedule
    Arr_info_txt,title = readdlm(ArrAdd,',',header = true);
    F = size(Arr_info_txt)[1];
    # obtain each flight's ID
    flCarrInd,flNoInd,rawDeptInd,rawArrInd,rawElapseInd = indexin(["UNIQUE_CARRIER","FL_NUM","CRS_DEP_TIME","CRS_ARR_TIME","CRS_ELAPSED_TIME"],title);
    AFlightID = [string(Arr_info_txt[i,flCarrInd],"_",Arr_info_txt[i,flNoInd]) for i in 1:F];
    rawArrSeq = Arr_info_txt[1:F,rawArrInd];
    FSI2 = [];
    # separate the exempted flights (flight time >= 4hrs)
    for i in 1:F
        if (Arr_info_txt[i,rawElapseInd] >= 240)
            push!(FSI2,i);
        end
    end
    FSI1 = setdiff(1:F,FSI2);
    # obtain the landing time of all flights LC[i], scheduled departure time S[i], and duration tau[i]
    LC = Dict();
    tau = Dict();
    S = Dict();
    Fexclude = [];
    for i in 1:F
        tp = Int64(div(rawArrSeq[i],100) * 2 + round(mod(rawArrSeq[i],100)/30) + 1);
        if tp <= totalT
            # planned arrival time
            LC[i] = tp;
            # flight time
            tau[i] = Int64(round(Arr_info_txt[i,rawElapseInd]/30));
            # take off time
            S[i] = Int64(LC[i] - tau[i]);
            if i in FSI1
                if (LC[i] - tau[i] <= N)
                    # exempt the flight which needs decision before time period 1
                    push!(FSI2,i);
                    FSI1 = setdiff(FSI1,[i]);
                end
            end
        else
            push!(Fexclude,i);
        end
    end
    FSI = setdiff(1:F,Fexclude);
    FSI1 = setdiff(FSI1,Fexclude);
    FSI2 = setdiff(FSI2,Fexclude);

    # read in the original departure flight schedule
    Dept_info_txt,title = readdlm(DeptAdd,',',header = true);
    F3 = size(Dept_info_txt)[1];
    flCarrInd,flNoInd,rawDeptInd,rawArrInd,rawElapseInd = indexin(["UNIQUE_CARRIER","FL_NUM","CRS_DEP_TIME","CRS_ARR_TIME","CRS_ELAPSED_TIME"],title);
    DFlightID = [string(Dept_info_txt[i,flCarrInd],"_",Dept_info_txt[i,flNoInd]) for i in 1:F3];
    rawDeptSeq = Dept_info_txt[1:F3,rawDeptInd];
    FSI3 = 1:F3;
    TS = Dict();
    F3exclude = [];
    for i in FSI3
        tp = Int64(div(rawDeptSeq[i],100) * 2 + round(mod(rawDeptSeq[i],100)/30) + 1);
        if tp <= totalT
            TS[i] = tp;
        else
            push!(F3exclude,i);
        end
    end
    FSI3 = setdiff(FSI3,F3exclude);

    return FSI1,FSI2,FSI3,FSI,LC,S,TS,tau,capDict,probDict
end

function genCap(mg,ct,gT,capD,probD)
    # return M sample paths
    scenList = zeros(mg,gT);
    probMat = rand(Uniform(0,1),mg,gT);
    for t in 1:gT
        for i in 1:mg
            iter = 0;
            probU = probMat[i,t];
            while probU >= 0
                iter = iter + 1;
                probU = probU - probD[ct + t - 1][iter];
            end
            scenList[i,t] = capD[ct + t - 1][iter];
        end
    end
    return scenList
end

function initPre(M,ct,totalT,N,LC,S,TS,tau,FSIP1,FSIP2,FSIP3,FSIP)
  # construct previous solution for the entire forward loop
  HX = Dict();
  HY = Dict();
  HZ = Dict();
  HE = Dict();
  HEZ = Dict();
  for f in FSIP
    HX[f] = zeros(tau[f]+N+1);
    HY[f] = 0;
  end
  for f in FSIP1
    HZ[f] = 0;
  end
  for f in FSIP3
    HE[f] = 0;
    HEZ[f] = 0;
  end
  emptySol = solType(HX,HY,HZ,HE,HEZ);
  entireSol = Dict();
  for i in 1:M
    for t in ct:totalT
      entireSol[i,t] = emptySol;
    end
  end

  # fix the first time period: HX!!!!!!!!

  return entireSol;
end

function createTail(ct,totalT,N,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,g,a,c,tc,cz,CR)
    # this function should create the problem structure of every time period from ct + T + 1 to totalT
    # it shoud leave the capacity information to simulation and x[t-1] to the previous stage solutions
    # build up the tail problem
    m = Model();
    # set up the variables
    @variable(m,X[FSM1,ct:totalT],Bin);    # clearance
    @variable(m,D[FSM1,(ct-1):totalT],Bin);    # departure
    @variable(m,Y[FSM,(ct-1):totalT],Bin);     # landing
    @variable(m,Z[FSM1,(ct-1):totalT],Bin);    # cancellation
    @variable(m,L[FSM,(ct-1):totalT],Bin);     # arrival
    @variable(m,E[FSM3,(ct-1):totalT],Bin);    # taking off
    @variable(m,EZ[FSM3],(ct-1):totalT,Bin);   # cancellation of taking off

    # set up the variables: z variables (local copies of the last stage's state variables)
    @variable(m,HX[f in FSM,1:(N+tau[f]+1)],Bin);    # history: clearance, departure and arrival
    @variable(m,HY[FSM],Bin);     # landing
    @variable(m,HZ[FSM1],Bin);    # cancellation
    @variable(m,HE[FSM3],Bin);    # taking off
    @variable(m,HEZ[FSM3],Bin);   # cancellation of takeoff

    @variable(m,R1[FSM],Bin);    # emergency outlet of landing
    addCost1H = @expression(m,addCost1,sum(R1[f]*CR for f in FSM));
    # every flight will eventually land/be cancelled/fly to emergency outlet
    @constraint(m,termCond1[f in FSM1],Z[f,totalT]+Y[f,totalT]+R1[f] == 1);
    @constraint(m,termCond2[f in FSM2],Y[f,totalT]+R1[f] == 1);
    @constraint(m,termCond3[f in FSM3],E[f,totalT]+EZ[f,totalT] == 1);

    # set up the objective function
    gdpCostH = @expression(m,gdpCost,sum(sum(gC[f,t]*(D[f,t] - D[f,t-1]) for t in max(S[f],ct):totalT) for f in FSM1));
    cancelCostH = @expression(m,cancelCost,sum(sum(c[f,t]*(Z[f,t] - Z[f,t-1]) for t in ct:totalT) for f in FSM1) + sum(sum(cz[f,t]*(EZ[f,t] - EZ[f,t-1]) for t in ct:T) for f in FSM3));
    airborneCostH = @expression(m,airborneCost,sum(sum(a[f]*(L[f,t] - Y[f,t]) for t in max(LC[f],ct):totalT) for f in FSM));
    taxiCostH = @expression(m,taxiCost,sum(sum(tc[f,t]*(E[f,t] - E[f,t-1]) for t in max(ct,TS[f]):totalT) for f in FSM3));
    @objective(m,Min,gdpCost+cancelCost+airborneCost+taxiCost+addCost1);

    # set up the constraints
    @constraint(m,noCancel[f in FSM1, t in ct:totalT], Z[f,t] + X[f,t] <= 1);
    @constraint(m,landAfter[f in FSM, t in ct:totalT], Y[f,t] <= L[f,t]);
    @constraint(m,planDept1[f in FSM1, t in ct:totalT;t - ct < N], D[f,t] == HX[f,ct-(t-N)]);
    @constraint(m,planDept2[f in FSM1, t in ct:totalT;t - ct >= N], D[f,t] == X[f,t-N]);
    @constraint(m,planLand1[f in FSM,t in ct:totalT;t - ct < tau[f]], L[f,t] == HX[f,ct-(t-tau[f]-N)]);
    @constraint(m,planLand2[f in FSM,t in ct:totalT;t - ct >= tau[f]], L[f,t] == D[f,t-tau[f]]);
    @constraint(m,noCancel[f in FSM3,t in ct:totalT], EZ[f,t] + E[f,t] <= 1);
    @constraint(m,capArr[t in ct:totalT], sum(Y[f,t] - Y[f,t-1] for f in FSM) <= 0);        # RHS change pending
    @constraint(m,capDept[t in ct:totalT], sum(E[f,t] - E[f,t-1] for f in FSM3) <= 0);      # RHS change pending
    @constraint(m,capTot[t in ct:totalT], sum(E[f,t] - E[f,t-1] for f in FSM3) + sum(Y[f,t] - Y[f,t-1] for f in FSM) <= 0);      # RHS change pending
    @constraint(m,propX1[f in FSM1, t = (ct+1):totalT], X[f,t] >= X[f,t-1]);
    @constraint(m,propX2[f in FSM1], X[f,ct] >= HX[f,1]);
    @constraint(m,propY[f in FSM, t = ct:totalT], Y[f,t] >= Y[f,t-1]);
    @constraint(m,propZ[f in FSM1, t = ct:totalT], Z[f,t] >= Z[f,t-1]);
    @constraint(m,propE[f in FSM3, t = ct:totalT], E[f,t] >= E[f,t-1]);
    @constraint(m,propEZ[f in FSM3, t = ct:totalT], EZ[f,t] >= EZ[f,t-1]);
    @constraint(m,F2Arr[f in FSM2, t = max(LC[f],currentT+T):totalT], L[f,t] == 1);
    @constraint(m,F2noArr[f in FSM2, t = ct:(LC[f]-1)], L[f,t] == 0);
    @constraint(m,noTakeoff[f in FSM1, t = ct:(S[f]-1)], D[f,t] == 0);
    @constraint(m,F3noDept[f in FSM3,t in ct:totalT;t<TS[f]],E[f,t] == 0);
    @constraint(m, initY[f in FSM], Y[f,ct - 1] == HY[f]);
    @constraint(m, initZ[f in FSM1], Z[f,ct - 1] == HZ[f]);
    @constraint(m, initE[f in FSM3], E[f,ct - 1] == HE[f]);
    @constraint(m, initEZ[f in FSM3], EZ[f,ct - 1] == HEZ[f]);

    # # create a local copy of the variables passed down
    @constraint(m,histShiftX[f in FSM,i in 1:(N+tau[f]+1)],HX[f,i] == 0);
    @constraint(m,histShiftY[f in FSM],HY[f] == 0);
    @constraint(m,histShiftZ[f in FSM1],HZ[f] == 0);
    @constraint(m,histShiftE[f in FSM3],HE[f] == 0);
    @constraint(m,histShiftEZ[f in FSM3],HEZ[f] == 0);

    return m
end

function createStream(ct,N,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,g,a,c,tc,cz)
    # this function should create the problem structure of every time period from ct to ct + T
    # it shoud leave the capacity information to simulation and x[t-1] to the previous stage solutions
    # with a tail
    # t is the current time period
    mo = Model();
    # set up the variables: x variables (variables of the current stage)
    @variable(mo,X[f in FSM,1:(N+tau[f]+1)],Bin);    # history: clearance, departure and arrival
    @variable(mo,Y[FSM],Bin);     # landing
    @variable(mo,Z[FSM1],Bin);    # cancellation
    @variable(mo,E[FSM3],Bin);    # taking off
    @variable(mo,EZ[FSM3],Bin);   # cancellation of takeoff
    @variable(mo,θ >= 0);

    # set up the variables: z variables (local copies of the last stage's state variables)
    @variable(mo,HX[f in FSM,1:(N+tau[f]+1)],Bin);    # history: clearance, departure and arrival
    @variable(mo,HY[FSM],Bin);     # landing
    @variable(mo,HZ[FSM1],Bin);    # cancellation
    @variable(mo,HE[FSM3],Bin);    # taking off
    @variable(mo,HEZ[FSM3],Bin);   # cancellation of takeoff

    # set up the objective function
    gdpCostH = @expression(mo,gdpCost,sum(gC[f,ct]*(X[f,N+1] - X[f,N+2]) for f in FSM1));
    cancelCostH = @expression(mo,cancelCost,sum(c[f,ct]*(Z[f]-HZ[f]) for f in FSM1)+sum(cz[f,ct]*(EZ[f] - HEZ[f]) for f in FSM3));
    airborneCostH = @expression(mo,airborneCost,sum(a[f]*(X[f,1+N+tau[f]] - Y[f]) for f in FSM));
    taxiCostH = @expression(mo,taxiCost,sum(tc[f,ct]*(E[f]-HE[f]) for f in FSM3));
    @objective(mo,Min,gdpCost+cancelCost+airborneCost+taxiCost+θ);

    @constraint(mo,noCancel1[f in FSM1],Z[f]+X[f,1] <= 1);
    @constraint(mo,noCancel2[f in FSM2],Z[f] == 0);
    @constraint(mo,preclear[f in FSM1;ct < S[f] - N],X[f,1] == 0);
    @constraint(mo,landAfter[f in FSM],Y[f] <= X[f,1+N+tau[f]]);
    @constraint(mo,noCancelD[f in FSM3],E[f] + EZ[f] <= 1);
    @constraint(mo,F3noDept[f in FSM3;t < TS[f]],E[f] == 0);

    # RHS are capacity forecast data
    @constraint(mo,capArr,sum(Y[f]-HY[f] for f in FSM) <= 0);
    @constraint(mo,capDept,sum((E[f]-HE[f]) for f in FSM3) <= 0);
    @constraint(mo,capTot,sum((Y[f]-HY[f]) for f in FSM) + sum((E[f]-HE[f]) for f in FSM3) <= 0);

    @constraint(mo,propX1[f in FSM],X[f,1] >= X[f,2]);
    @constraint(mo,propXr[f in FSM,i in 2:(N+tau[f]+1)],X[f,i] == HX[f,i-1]);
    @constraint(mo,propY[f in FSM],Y[f] >= HY[f]);
    @constraint(mo,propZ[f in FSM1],Z[f] >= HZ[f]);
    @constraint(mo,propE[f in FSM3],E[f] >= HE[f]);
    @constraint(mo,propEZ[f in FSM3],EZ[f] >= HEZ[f]);

    # create a local copy of the variables passed down
    @constraint(mo,histShiftX[f in FSM,i in 1:(N+tau[f]+1)],HX[f,i] == 0);
    @constraint(mo,histShiftY[f in FSM],HY[f] == 0);
    @constraint(mo,histShiftZ[f in FSM1],HZ[f] == 0);
    @constraint(mo,histShiftE[f in FSM3],HE[f] == 0);
    @constraint(mo,histShiftEZ[f in FSM3],HEZ[f] == 0);

    # don't add the cut constraints, leave it to the main function to add cuts

    return mo
end

function createEnd(ct,totalT,N,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,g,a,c,tc,CR)
    # this function should create the problem structure of every time period from ct to totalT (if totalT <= ct + T)
    # it shoud leave the capacity information to simulation and x[t-1] to the previous stage solutions
    # with no tail
    m = Model();
    # set up the variables
    @variable(m,Y[FSM],Bin);     # landing
    @variable(m,Z[FSM1],Bin);    # cancellation
    @variable(m,L[FSM],Bin);     # arrival
    @variable(m,E[FSM3],Bin);    # taking off
    @variable(m,EZ[FSM3],Bin);    # cancellation of taking off

    # set up the variables: z variables (local copies of the last stage's state variables)
    @variable(mo,HX[f in FSM,1:(N+tau[f]+1)],Bin);    # history: clearance, departure and arrival
    @variable(mo,HY[FSM],Bin);     # landing
    @variable(mo,HZ[FSM1],Bin);    # cancellation
    @variable(mo,HE[FSM3],Bin);    # taking off
    @variable(mo,HEZ[FSM3],Bin);   # cancellation of takeoff

    @variable(m,R1[FSM],Bin);    # emergency outlet of landing
    addCost1H = @expression(m,addCost1,sum(R1[f]*CR for f in FSM));
    # every flight will eventually land/be cancelled/fly to emergency outlet
    @constraint(m,termCond1[f in FSM1],Z[f]+Y[f]+R1[f] == 1);
    @constraint(m,termCond2[f in FSM2],Y[f]+R1[f] == 1);
    @constraint(m,termCond3[f in FSM3],E[f]+EZ[f] == 1);

    # set up the objective function
    cancelCostH = @expression(m,cancelCost,sum(c[f,ct]*(Z[f]-HZ[f]) for f in FSM1)+sum(cz[f,t]*(EZ[f]-HZ[f]) for f in FSM3));
    airborneCostH = @expression(m,airborneCost,sum(a[f]*(L[f] - Y[f]) for f in FSM));
    taxiCostH = @expression(m,taxiCost,sum(tc[f,ct]*(E[f]-HE[f]) for f in FSM3));
    @objective(m,Min,cancelCost+airborneCost+taxiCost+addCost1);

    @constraint(m,noCancel[f in FSM1],Z[f]+HX[f,1] <= 1);
    @constraint(m,landAfter[f in FSM],Y[f] <= L[f]);
    @constraint(m,planLand[f in FSM1],L[f] == HX[f,tau[f]+N]);
    @constraint(m,capArr,sum(Y[f] for f in FSM) <= 2000);    # RHS change pending
    @constraint(m,capDept,sum(E[f] for f in FSM3) <= 2000); # RHS change pending
    @constraint(m,capTot,sum(Y[f] for f in FSM) + sum(E[f] for f in FSM3) <= 2000);      # RHS change pending
    @constraint(m,propY[f in FSM],Y[f] >= HY[f]);
    @constraint(m,propZ[f in FSM1],Z[f] >= HZ[f]);
    @constraint(m,propE[f in FSM3],E[f] >= HE[f]);
    @constraint(m,propEZ[f in FSM3],EZ[f] >= HEZ[f]);

    # create a local copy of the variables passed down
    @constraint(m,histShiftX[f in FSM,i in 1:(N+tau[f]+1)],HX[f,i] == 0);
    @constraint(m,histShiftY[f in FSM],HY[f] == 0);
    @constraint(m,histShiftZ[f in FSM1],HZ[f] == 0);
    @constraint(m,histShiftE[f in FSM3],HE[f] == 0);
    @constraint(m,histShiftEZ[f in FSM3],HEZ[f] == 0);

    return m
end

function updateUB(X,Y,Z,D,E,L,mUB,FSUB1,FSUB2,FSUB3,FSUB,LC,S,TS,capDict,probDict,gUB,aUB,cUB,tcUB)
    # this is the function that calculates the upper bound in an SDDP iteration
end

function GDP_Main(totalT,T,currentT,N,M,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,capDict,probDict)
    # this is the function that carries out the SDDP and output the solution
    # totalT is the entire horizon, T is the length of the rolling horizon
    # N is the lag of decision, M is the number of threads

    # one to one mapping between scenario and capacity
#    totalCapDict = Dict(1=>107,2=>97,3=>92,4=>84,
#                    5=>65,6=>59,7=>56,8=>51,
#                    9=>25,10=>23,11=>21,12=>20,
#                    13=>90,14=>82,15=>77,16=>71,
#                    17=>85,18=>77,19=>73,20=>67,
#                    21=>15,22=>14,23=>13,24=>12,
#                    25=>55,26=>50,27=>47,28=>43,
#                    29=>21,30=>19,31=>18,32=>16,
#                    33=>71,34=>64,35=>61,36=>56,
#                    37=>13,38=>12,39=>11,40=>10);
#    ArrCapDict = Dict();
#    DeptCapDict = Dict();
#    for i in 1:40
#        ArrCapDict[i] = round(totalCapDict[i]*60/107);
#        DeptCapDict[i] = round(totalCapDict[i]*70/107);
#    end

    # use pilot data
    totalCapDict = Dict(1=>6,2=>5,3=>3);
    ArrCapDict = Dict(1=>4,2=>3,3=>2);
    DeptCapDict = Dict(1=>4,2=>3,3=>2);

    # set up the default solver as CbcSolver
    solver = CplexSolver(seconds = 9000);
    ub = 10000000000;
    lb = 0;
    iterNo = 0;
    ϵ = 0.05;
    # generate costs based on their scheduled departure
    gM,aM,cM,tcM,czM,rM = generateCost(currentT,totalT,LC,S,TS,FSM1,FSM2,FSM3,FSM);
    # need a variable to store the cuts, keys are time periods the cuts are for
    cutList = Dict();

    # precreate the forward problem structure for every time stage
    # m is the dictionary that stores the forward problem structure
    mf = Dict();
    if currentT + T - 1 <= totalT
        endT = currentT + T - 1;
        for t = currentT:endT
          # create the template problem for each time period
          mf[t] = createStream(t,N,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,gM,aM,cM,tcM,1000);
        end
        mt = createTail(endT+1,totalT,N,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,gM,aM,cM,tcM,1000);
    else
        endT = totalT;
        for t = currentT:endT
            if t < endT
                mf[t] = createStream(t,N,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,gM,aM,cM,tcM,1000);
            else
                mf[t] = createEnd(t,totalT,N,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,gM,aM,cM,tcM,1000);
            end
        end
    end

    # if upper bound and lower bound are close enough or the running iteration limit is hit, stop
    while ((ub - lb)/lb >= ϵ) || (iterNo <= 500)
        # sample M scenarios
        iterNo = iterNo + 1;
        if currentT + T <= totalT
            scenList = genCap(M,currentT,T,capDict,probDict);
            tailList = Dict();
            for t in (currentT + T):totalT
                tailList[t] = indmax(probDict[t]);
            end
        else
            scenList = genCap(M,currentT,totalT - currentT + 1,capDict,probDict);
        end

        # forward step
        Xpre,Ypre,Zpre,Dpre,Epre,Lpre = initPre(totalT,currentT,M,FSM1,FSM2,FSM3,FSM);
        for k = 1:M
            if currentT + T - 1 <= totalT
                endT = currentT + T - 1;
                for t = currentT:endT
                    # change RHS for each time period
                    # change the RHS for capacity constraints
                    JuMP.setRHS(mf[t].conDict[:capArr],ArrCapDict[scenList[k,t]]);
                    JuMP.setRHS(mf[t].conDict[:capDept],DeptCapDict[scenList[k,t]]);
                    JuMP.setRHS(mf[t].conDict[:capTot],totalCapDict[scenList[k,t]]);
                    if t >= N+1
                        for f in FSM1
                            JuMP.setRHS(mf[t].conDict[:planDept][f],Xpre[k,f,t - N]);
                        end
                    end
                    for f in FSM1
                        if t >= tau[f]
                            JuMP.setRHS(mf[t].conDict[:planLand][f],Dpre[k,f,t - tau[f]]);
                        end
                    end
                    for f in FSM1
                        JuMP.setRHS(mf[t].conDict[:propX][f],Xpre[k,f,t - 1]);
                        JuMP.setRHS(mf[t].conDict[:propZ][f],Zpre[k,f,t - 1]);
                    end
                    for f in FSM
                        JuMP.setRHS(mf[t].conDict[:propY][f],Ypre[k,f,t - 1]);
                    end
                    for f in FSM3
                        JuMP.setRHS(mf[t].conDict[:propE][f],Epre[k,f,t - 1]);
                    end

                    # solve the problem
                    solve(mf[t]);

                    # record each scenario stream's optimal value and optimal solutions
                    for f in FSM1
                        Xpre[k,f,t] = getvalue(mf[t].varDict[:X][f]);
                        Zpre[k,f,t] = getvalue(mf[t].varDict[:Z][f]);
                        Dpre[k,f,t] = getvalue(mf[t].varDict[:D][f]);
                    end
                    for f in FSM
                        Ypre[k,f,t] = getvalue(mf[t].varDict[:Y][f]);
                        Lpre[k,f,t] = getvalue(mf[t].varDict[:L][f]);
                    end
                    for f in FSM3
                        Epre[k,f,t] = getvalue(mf[t].varDict[:E][f]);
                    end
                end

                # change RHS for the tail problem
                for t in (currentT + T):totalT
                    JuMP.setRHS(mt.conDict[:capArr][t],ArrCapDict[tailList[t]]);
                    JuMP.setRHS(mt.conDict[:capDept][t],DeptCapDict[tailList[t]]);
                    JuMP.setRHS(mt.conDict[:capTot][t],totalCapDict[tailList[t]]);
                end

                for f in FSM1
                    JuMP.setRHS(mt.conDict[:initX][f],Xpre[f,currentT+T-1]);
                    JuMP.setRHS(mt.conDict[:initZ][f],Zpre[f,currentT+T-1]);
                end
                for f in FSM
                    JuMP.setRHS(mt.conDict[:initY][f],Ypre[f,currentT+T-1]);
                end
                for f in FSM3
                    JuMP.setRHS(mt.conDict[:initE][f],Epre[f,currentT+T-1]);
                end

                for t in currentT+T:totalT
                    if t - currentT - T < N
                        for f in FSM1
                            JuMP.setRHS(mt.conDict[:planDept][f,t],Xpre[f,t-N]);
                        end
                    end
                    if t - currentT - t < tau[f]
                        for f in FSM1
                            JuMP.setRHS(mt.conDict[:planLand][f,t],Dpre[f,t-tau[f]]);
                        end
                    end
                end

                # solve the tail problem
                solve(mt);

                # record the tail problem optimal solutions
                for t in currentT+T:totalT
                    for f in FSM1
                        Xpre[k,f,t] = getvalue(mt.varDict[:X][f,t]);
                        Zpre[k,f,t] = getvalue(mt.varDict[:Z][f,t]);
                        Dpre[k,f,t] = getvalue(mt.varDict[:D][f,t]);
                    end
                    for f in FSM
                        Ypre[k,f,t] = getvalue(mt.varDict[:Y][f,t]);
                        Lpre[k,f,t] = getvalue(mt.varDict[:L][f,t]);
                    end
                    for f in FSM3
                        Epre[k,f,t] = getvalue(mt.varDict[:E][f,t]);
                    end
                end

            else
                endT = totalT;
                for t = currentT:endT
                    # change RHS for each time period
                    # change the RHS for capacity constraints
                    JuMP.setRHS(mf[t].conDict[:capArr],ArrCapDict[scenList[k,t]]);
                    JuMP.setRHS(mf[t].conDict[:capDept],DeptCapDict[scenList[k,t]]);
                    JuMP.setRHS(mf[t].conDict[:capTot],totalCapDict[scenList[k,t]]);
                    if t >= N
                        for f in FSM1
                            JuMP.setRHS(mf[t].conDict[:planDept][f],Xpre[k,f,t - N]);
                        end
                    end
                    for f in FSM1
                        if t >= tau[f]
                            JuMP.setRHS(mf[t].conDict[:planLand][f],Dpre[k,f,t - tau[f]]);
                        end
                    end
                    for f in FSM1
                        JuMP.setRHS(mf[t].conDict[:propX][f],Xpre[k,f,t - 1]);
                        JuMP.setRHS(mf[t].conDict[:propZ][f],Zpre[k,f,t - 1]);
                    end
                    for f in FSM
                        JuMP.setRHS(mf[t].conDict[:propY][f],Ypre[k,f,t - 1]);
                    end
                    for f in FSM3
                        JuMP.setRHS(mf[t].conDict[:propE][f],Epre[k,f,t - 1]);
                    end

                    # solve the problem
                    solve(mf[t]);

                    # record each scenario stream's optimal value and optimal solutions
                    for f in FSM1
                        Xpre[k,f,t] = getvalue(mf[t].varDict[:X][f]);
                        Zpre[k,f,t] = getvalue(mf[t].varDict[:Z][f]);
                        Dpre[k,f,t] = getvalue(mf[t].varDict[:D][f]);
                    end
                    for f in FSM
                        Ypre[k,f,t] = getvalue(mf[t].varDict[:Y][f]);
                        Lpre[k,f,t] = getvalue(mf[t].varDict[:L][f]);
                    end
                    for f in FSM3
                        Epre[k,f,t] = getvalue(mf[t].varDict[:E][f]);
                    end
                end
            end
        end

        # when a certain criterion is met (every 10 iteration), update the upperbound with 50 streams
        if mod(iterNo,10) == 0
            M1 = 50;
            ub = updateUB(M1,FSM1,FSM2,FSM3,FSM,LC,S,TS,capDict,probDict,gM,aM,cM,tcM);
        end

        # backward step
        for t = T:-1:currentT
            for k = 1:M
                for j = 1:length(probDict[t])
                    # solve the relaxation to generate cuts
                end
                # update the problem with generated cuts
            end
        end

        # update the lower bound
    end
    return
end

function updateSet(totalT,currentT,FSU1,FSU2,FSU3,FSU,X,Y,Z,D,L,E,capAddress,capProbAdd)
    # this is the function that updates the set for the next time period in the horizon
end
