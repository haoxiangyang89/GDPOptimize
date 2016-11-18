# This is the SDDP implementation of the GDP optimization model
using JuMP,Cbc,PyPlot,DataFrames,RDatasets,Distributions;

function genCap(M,T,capD,probD)
    # return M sample paths
    scenList = zeros(M,T);
    probMat = rand(Uniform(0,1),M,T);
    for t in 1:T
        for i in 1:M
            iter = 0;
            probU = probMat[i,t];
            while probU >= 0
                iter = iter + 1;
                probU = probU - probD[t][iter];
            end
            scenList[i,t] = capD[t][iter];
        end
    end
    return scenList
end

function createStream(t,N,S,LC,TS,tau,FSet1,FSet2,FSet3,FSet,g,c,a,tc,CR)
    m = Model();
    # set up the variables
    @variable(m,X[FSet1],Bin);    # clearance
    @variable(m,D[FSet1],Bin);    # departure
    @variable(m,Y[FSet],Bin);     # landing
    @variable(m,Z[FSet1],Bin);    # cancellation
    @variable(m,L[FSet],Bin);     # arrival
    @variable(m,E[FSet3],Bin);    # taking off
    @variable(m,θ >= 0);
    if t == T
        @variable(m,R1[FSet],Bin);    # emergency outlet of landing
        @variable(m,R2[FSet3],Bin);   # emergency outlet of taking off
        addCost1H = @expression(m,addCost1,sum{R1[f]*CR,f in FSet});
        addCost2H = @expression(m,addCost2,sum{R2[f]*CR,f in FSet3});
        @constraint(m,termCond1[f in FSet],Z[f]+Y[f]+R1[f] == 1);
        @constraint(m,termCond1[f in FSet],E[f]+R2[f] == 1);
    else
        addCost1H = @expression(m,addCost1,0);
        addCost2H = @expression(m,addCost2,0);
    end

    gdpCostH = @expression(m,gdpCost,sum{g[f,t]*D[f],f in FSet1});
    cancelCostH = @expression(m,cancelCost,sum{c[f,t]*Z[f],f in FSet1});
    airborneCostH = @expression(m,airborneCost,sum{a[f]*(L[f] - Y[f]),f in FSet});
    taxiCostH = @expression(m,taxiCost,sum{tc[f]*E[f],f in FSet3});
    @objective(m,Min,gdpCost+cancelCost+airborneCost+taxiCost+addCost1+addCost2+θ);

    @constraint(m,noCancel[f in FSet1],Z[f]+D[f] <= 1);
    @constraint(m,landAfter[f in FSet],Y[f] <= L[f]);

    for f in FSet1
        if t <= S[f]-1
            @constraint(m,noTakeoff[f],D[f] == 0);
        end
        if t >= tau[f]+1
            @constraint(m,planLand[f in FSet1],L[f] == 0);    # RHS change pending
        end
        if t >= N+1
            @constraint(m,planDept[f in FSet1],D[f] == 0);    # RHS change pending
        end
    end
    for f in FSet2
        if t >= LC[f]
            @constraint(m,F2Arr[f],L[f] == 1);
        else
            @constraint(m,F2noArr[f],L[f] == 0);
        end
    end
    for f in FSet3
        if t < TS[f]
            @constraint(m,F3noDept[f],E[f] == 0);
        end
    end
    @constraint(m,capArr,sum{Y[f],f in FSet} <= 2000);    # RHS change pending
    @constraint(m,capDept,sum{E[f], f in FSet3} <= 2000); # RHS change pending
    @constraint(m,capTot,sum{Y[f],f in FSet} + sum{E[f], f in FSet3} <= 2000);      # RHS change pending
    @constraint(m,propX[f in FSet1],X[f] >= 0);     # RHS change pending
    @constraint(m,propY[f in FSet],Y[f] >= 0);      # RHS change pending
    @constraint(m,propZ[f in FSet1],Z[f] >= 0);     # RHS change pending
    @constraint(m,propE[f in FSet3],E[f] >= 0);     # RHS change pending
    return m
end

function sddpGDP(T::Int64,N::Int64,M::Int64,capAddress::ASCIIString,capProbAdd::ASCIIString,ArrAdd::ASCIIString,DeptAdd::ASCIIString)
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
    for t = 1:T
        capTemp = [];
        probTemp = [];
        for j in capacity_info_txt[t,2:length(capacity_info_txt[t,:])]
            if (typeof(j) == Int)
                push!(capTemp,j);
            end
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
    FlightID = [string(Arr_info_txt[i,flCarrInd],"_",Arr_info_txt[i,flNoInd]) for i in 1:F];
    rawArrSeq = Arr_info_txt[1:F,rawArrInd];
    FSet2 = [];
    # separate the exempted flights
    for i in 1:F
        if (Arr_info_txt[i,rawElapseInd] >= 240)
            push!(FSet2,i);
        end
    end
    FSet1 = setdiff(1:F,FSet2);
    # obtain the landing time of all flights LC[i], scheduled departure time S[i], and duration tau[i]
    LC = Dict();
    tau = Dict();
    S = Dict();
    Fexclude = [];
    for i in 1:F
        tp = Int64(div(rawArrSeq[i],100) * 2 + round(mod(rawArrSeq[i],100)/30) + 1);
        if tp <= T
            LC[i] = tp;
            tau[i] = Int64(round(Arr_info_txt[i,rawElapseInd]/30));
            S[i] = Int64(LC[i] - tau[i]);
            if i in FSet1
                if (LC[i] - tau[i] <= N)
                    # exempt the flight which needs decision before time period 1
                    push!(FSet2,i);
                    FSet1 = setdiff(FSet1,[i]);
                end
            end
        else
            push!(Fexclude,i);
        end
    end
    FSet = setdiff(1:F,Fexclude);
    FSet1 = setdiff(FSet1,Fexclude);
    FSet2 = setdiff(FSet2,Fexclude);

    # read in the original departure flight schedule
    Dept_info_txt,title = readdlm(DeptAdd,',',header = true);
    F3 = size(Dept_info_txt)[1];
    flCarrInd,flNoInd,rawDeptInd,rawArrInd,rawElapseInd = indexin(["UNIQUE_CARRIER","FL_NUM","CRS_DEP_TIME","CRS_ARR_TIME","CRS_ELAPSED_TIME"],title);
    FlightID = [string(Dept_info_txt[i,flCarrInd],"_",Dept_info_txt[i,flNoInd]) for i in 1:F3];
    rawDeptSeq = Dept_info_txt[1:F3,rawDeptInd];
    FSet3 = 1:F3;
    TS = Dict();
    F3exclude = [];
    for i in FSet3
        tp = Int64(div(rawDeptSeq[i],100) * 2 + round(mod(rawDeptSeq[i],100)/30) + 1);
        if tp <= T
            TS[i] = tp;
        else
            push!(F3exclude,i);
        end
    end
    FSet3 = setdiff(FSet3,F3exclude);

    # input the cost of ground delay, airborne delay, taxi-out delay and cancellation
    # g: ground delay cost
    # a: airborne cost
    # c: cancellation cost
    # tc: taxi-out cost
    g = zeros(F,T);
    a = zeros(F);
    c = 200*ones(F,T);
    for f in 1:F
        a[f] = 8;
    end
    for f in FSet1
        for t in S[f]+1:T
            g[f,t] = 1*(t-S[f]);
        end
        for t in 1:T
            c[f,t] = 20;
        end
    end
    tc = zeros(F3);
    for f in FSet3
        tc[f] = 4;
    end
    CR = 150;

    # one to one mapping between scenario and capacity
    totalCapDict = Dict(1=>107,2=>97,3=>92,4=>84,
                    5=>65,6=>59,7=>56,8=>51,
                    9=>25,10=>23,11=>21,12=>20,
                    13=>90,14=>82,15=>77,16=>71,
                    17=>85,18=>77,19=>73,20=>67,
                    21=>15,22=>14,23=>13,24=>12,
                    25=>55,26=>50,27=>47,28=>43,
                    29=>21,30=>19,31=>18,32=>16,
                    33=>71,34=>64,35=>61,36=>56,
                    37=>13,38=>12,39=>11,40=>10);
    ArrCapDict = Dict();
    DeptCapDict = Dict();
    for i in 1:40
        ArrCapDict[i] = round(totalCapDict[i]*60/107);
        DeptCapDict[i] = round(totalCapDict[i]*70/107);
    end

    # initialize the deterministic model for forward iteration
    solver = CbcSolver(seconds = 9000);

    # set up the upper bound and the lower bound
    ub = 10000*(F+F3);
    lb = 0;

    # while the stopping criteria is not met
    ϵ = 0.05;
    XSol = Dict();
    YSol = Dict();
    ZSol = Dict();
    LSol = Dict();
    DSol = Dict();
    ESol = Dict();
    for t in 0:T
        XSol[t] = zeros(M,F);
        YSol[t] = zeros(M,F);
        ZSol[t] = zeros(M,F);
        LSol[t] = zeros(M,F);
        DSol[t] = zeros(M,F);
        ESol[t] = zeros(M,F3);
    end
    while (ub - lb)/lb >= ϵ
        # forward iteration
        # simulate M sample paths
        scenList = genCap(M,T,capDict,probDict);
        solBar = [];
        for i in 1:M
            for t in 1:T
                m = createStream(t,N,S,LC,TS,tau,FSet1,FSet2,FSet3,FSet,g,c,a,tc,CR);
                # change the RHS
                for f in FSet1
                    if t >= N + 1
                        JuMP.setRHS(m.conDict[:planDept][f],XSol[t - N][i,f]);
                    if t >= tau[f] + 1
                        JuMP.setRHS(m.conDict[:planLand][f],DSol[t - tau[f]][i,f]);
                    JuMP.setRHS(m.conDict[:propX][f],XSol[t - 1][i,f]);
                    JuMP.setRHS(m.conDict[:propZ][f],ZSol[t - 1][i,f]);
                end
                for f in FSet
                    JuMP.setRHS(m.conDict[:propY][f],YSol[t - 1][i,f]);
                end
                for f in FSet3
                    JuMP.setRHS(m.conDict[:propE][f],ESol[t - 1][i,f]);
                end

                JuMP.setRHS(m.conDict[:capArr],ArrCapDict[scenList[i,t]]);
                JuMP.setRHS(m.conDict[:capDept],DeptCapDict[scenList[i,t]]);
                JuMP.setRHS(m.conDict[:capTot],totalCapDict[scenList[i,t]]);

                # solve each problem and record the solutions
                solve(m);
                push!(solBar,m.varDict);
            end
        end

        # solve each of the M problem

        for i in 1:M

            # record the solutions

        end

        # update the upper bound

        # backward iteration

        # update the lower bound
    end
end
