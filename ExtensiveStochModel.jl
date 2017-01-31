using JuMP,Cbc,DataFrames,RDatasets;

function solveStochPre(N,ArrAdd,DeptAdd,capAdd,connAdd)
    capType = readdlm(capAdd,',',header = false);
    connMat = readdlm(connAdd,',',header = false);
    connMat = round(Int64,connMat);
    M,totalT = size(capType);
    # full size dictionary
    #totalCapDict = Dict(1=>107,2=>97,3=>92,4=>84,
    #                5=>65,6=>59,7=>56,8=>51,
    #                9=>25,10=>23,11=>21,12=>20,
    #                13=>90,14=>82,15=>77,16=>71,
    #                17=>85,18=>77,19=>73,20=>67,
    #                21=>15,22=>14,23=>13,24=>12,
    #                25=>55,26=>50,27=>47,28=>43,
    #                29=>21,30=>19,31=>18,32=>16,
    #                33=>71,34=>64,35=>61,36=>56,
    #                37=>13,38=>12,39=>11,40=>10);

    # pilot dictionary
    totalCapDict = Dict(1=>6,2=>5,3=>3);
    ArrCapDict = Dict(1=>4,2=>3,3=>2);
    DeptCapDict = Dict(1=>4,2=>3,3=>2);
    #for i in 1:40
    #    ArrCapDict[i] = round(totalCapDict[i]*60/107);
    #    DeptCapDict[i] = round(totalCapDict[i]*70/107);
    #end
    capA = zeros(M,totalT);
    capD = zeros(M,totalT);
    capT = zeros(M,totalT);
    for m in 1:M
        for t in 1:totalT
            capA[m,t] = ArrCapDict[capType[m,t]];
            capD[m,t] = DeptCapDict[capType[m,t]];
            capT[m,t] = totalCapDict[capType[m,t]];
        end
    end

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
        adjustedTime = rawArrSeq[i];
        tp = Int64(div(adjustedTime,100) * 2 + floor(mod(adjustedTime,100)/30) + 1);
        if tp <= totalT
            LC[i] = tp;
            tau[i] = Int64(round(Arr_info_txt[i,rawElapseInd]/30));
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
        adjustedTime = rawDeptSeq[i];
        tp = Int64(div(adjustedTime,100) * 2 + floor((mod(adjustedTime,100)+0.001)/30) + 1);
        if tp <= totalT
            TS[i] = tp;
        else
            push!(F3exclude,i);
        end
    end
    FSI3 = setdiff(FSI3,F3exclude);

    return FSI1,FSI2,FSI3,FSI,AFlightID,DFlightID,LC,S,TS,tau,capA,capD,capT,totalT,M,connMat
end

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

# use 30 mins as a time period. the planning span is 2 hours.
function solveStoch(currentT,T,N,M,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,capA,capD,capT,connMat)
    g,a,c,tc,cz,r = generateCost(currentT,T,LC,S,TS,FSM1,FSM2,FSM3,FSM);
    # set up the capacity
    # right now we set it up as it can handle all flights (A[t] = 90 for all t), we can tune the capacity later
    TSet = currentT:T;

    # set up the model
    md = Model();
    solver = CbcSolver(seconds = 10000.0);

    # set up variables
    @variable(md,X[FSM1,(currentT - 1):T,1:M],Bin);
    @variable(md,D[FSM1,(currentT - 1):T,1:M],Bin);
    @variable(md,Z[FSM1,(currentT - 1):T,1:M],Bin);
    @variable(md,L[FSM,(currentT - 1):T,1:M],Bin);
    @variable(md,Y[FSM,(currentT - 1):T,1:M],Bin);
    @variable(md,E[FSM3,(currentT - 1):T,1:M],Bin);
    @variable(md,EZ[FSM3,(currentT - 1):T,1:M],Bin);
    @variable(md,R[FSM,1:M],Bin);

    # set up objective functions
    @expression(md,gdpCost[m in 1:M],sum{sum{g[f,t]*(D[f,t,m] - D[f,t-1,m]),t in max(S[f]-N,currentT):T},f in FSM1});
    @expression(md,cancelCost[m in 1:M],sum{sum{c[f,t]*(Z[f,t,m] - Z[f,t-1,m]), t in currentT:T}, f in FSM1} + sum{sum{cz[f,t]*(EZ[f,t,m] - EZ[f,t-1,m]), t in currentT:T}, f in FSM3});
    @expression(md,airborneCost[m in 1:M],sum{sum{a[f]*(L[f,t,m] - Y[f,t,m]) ,t in max(LC[f],currentT):T} ,f in FSM});
    @expression(md,taxiCost[m in 1:M],sum{sum{tc[f,t]*(E[f,t,m] - E[f,t-1,m]),t in max(TS[f],currentT):T},f in FSM3});
    @expression(md,rerouteCost[m in 1:M],sum{r[f]*R[f,m],f in FSM});

    @objective(md,Min,1/M*sum{gdpCost[m] + cancelCost[m] + airborneCost[m] + taxiCost[m] + rerouteCost[m],m in 1:M});

    # set up constraints
    @constraint(md,mustLand1[f in FSM1,m in 1:M], Y[f,T,m] + Z[f,T,m] == 1);
    @constraint(md,mustLand2[f in FSM2,m in 1:M], Y[f,T,m] == 1);
    @constraint(md,mustTakeoff[f in FSM3,m in 1:M], E[f,T,m] + EZ[f,T,m] == 1);
    @constraint(md,noCancel[f in FSM1, t in currentT:T,m in 1:M], Z[f,t,m] + D[f,t,m] <= 1);
    @constraint(md,noCancel2[f in FSM3, t in currentT:T,m in 1:M], EZ[f,t,m] + E[f,t,m] <= 1);
    @constraint(md,landAfter[f in FSM, t in currentT:T,m in 1:M], Y[f,t,m] <= L[f,t,m]);
    @constraint(md,planDept[f in FSM1, t in currentT:(T-N),m in 1:M], X[f,t,m] == D[f,t+N,m]);
    @constraint(md,planLand[f in FSM1, t in currentT:(T-tau[f]),m in 1:M], D[f,t,m] == L[f,t + tau[f],m]);
    @constraint(md,capArr[t in TSet,m in 1:M], sum{Y[f,t,m] - Y[f,t-1,m],f in FSM} <= capA[m,t - currentT + 1]);
    @constraint(md,capDept[t in TSet,m in 1:M], sum{E[f,t,m] - E[f,t-1,m],f in FSM3} <= capD[m,t - currentT + 1]);
    @constraint(md,capTot[t in TSet,m in 1:M], sum{Y[f,t,m] - Y[f,t-1,m],f in FSM} + sum{E[f,t,m] - E[f,t-1,m],f in FSM3} <= capT[m,t - currentT + 1]);
    @constraint(md,propX[f in FSM1, t in TSet,m in 1:M], X[f,t,m] >= X[f,t-1,m]);
    @constraint(md,propY[f in FSM, t in TSet,m in 1:M], Y[f,t,m] >= Y[f,t-1,m]);
    @constraint(md,propZ[f in FSM1, t in TSet,m in 1:M], Z[f,t,m] >= Z[f,t-1,m]);
    @constraint(md,propE[f in FSM3, t in TSet,m in 1:M], E[f,t,m] >= E[f,t-1,m]);
    @constraint(md,propEZ[f in FSM3, t in TSet,m in 1:M], EZ[f,t,m] >= EZ[f,t-1,m]);
    @constraint(md,F2Arr[f in FSM2, t in LC[f]:T,m in 1:M], L[f,t,m] == 1);
    @constraint(md,F2noArr[f in FSM2, t in (currentT - 1):LC[f]-1,m in 1:M], L[f,t,m] == 0);
    @constraint(md,F1noDept[f in FSM1, t in currentT:min(currentT+N-1,T),m in 1:M], D[f,t,m] == 0);
    @constraint(md,F1noArr[f in FSM1, t in currentT:min(currentT+N+tau[f]-1,T),m in 1:M], L[f,t,m] == 0);

    # set up auxiliary constraints
    # cannot take off before S[i]
    @constraint(md,noTakeoff[f in FSM1, t in currentT:(S[f]-1),m in 1:M], D[f,t,m] == 0);
    @constraint(md,noTakeoff2[f in FSM3, t in currentT:(TS[f]-1),m in 1:M], E[f,t,m] == 0);
    # initial condition
    @constraints(md,begin
        initX[f in FSM1,m in 1:M], X[f,currentT - 1,m] == 0
        initY[f in FSM,m in 1:M], Y[f,currentT - 1,m] == 0
        initZ[f in FSM1,m in 1:M], Z[f,currentT - 1,m] == 0
        initE[f in FSM3,m in 1:M], E[f,currentT - 1,m] == 0
        initEZ[f in FSM3,m in 1:M], EZ[f,currentT - 1,m] == 0
        end);

    # add the non-anticipativity constraints
    # original version with the third component is connMat[m,t]+1
    @constraint(md,nonAntiX[f in FSM1,t in TSet,m in 1:M], X[f,t,m] == X[f,t,connMat[m,t]]);
    @constraint(md,nonAntiY[f in FSM,t in TSet,m in 1:M], Y[f,t,m] == Y[f,t,connMat[m,t]]);
    @constraint(md,nonAntiZ[f in FSM1,t in TSet,m in 1:M], Z[f,t,m] == Z[f,t,connMat[m,t]]);
    @constraint(md,nonAntiE[f in FSM3,t in TSet,m in 1:M], E[f,t,m] == E[f,t,connMat[m,t]]);
    @constraint(md,nonAntiEZ[f in FSM3,t in TSet,m in 1:M], EZ[f,t,m] == EZ[f,t,connMat[m,t]]);

    # solve the deterministic model
    status = solve(md);

    # output the decision made in the first time period
    FS1exclude = [];
    FS2exclude = [];
    FS2excludeY = [];
    FS2excludeZ = [];
    CSCost = 0;
    gCost = 0;
    abCost = 0;
    ccCost = 0;
    txCost = 0;
    for f in FSM1
        if getvalue(X[f,currentT,1]) - getvalue(X[f,currentT-1,1]) == 1
            CSCost += g[f,currentT+N];
            gCost += g[f,currentT+N];
            push!(FS1exclude,f);
        end
        if getvalue(Z[f,currentT,1])- getvalue(Z[f,currentT-1,1]) == 1
            CSCost += c[f,currentT];
            ccCost += c[f,currentT];
            push!(FS2exclude,f);
            push!(FS2excludeZ,f);
        end
    end
    for f in FSM
        if getvalue(Y[f,currentT,1]) - getvalue(Y[f,currentT-1,1]) == 1
            CSCost += a[f]*(currentT - LC[f]);
            abCost += a[f]*(currentT - LC[f]);
            push!(FS2exclude,f);
            push!(FS2excludeY,f);
        end
    end
    FS3exclude = [];
    FS3excludeZ = [];
    for f in FSM3
        if (getvalue(E[f,currentT,1]) - getvalue(E[f,currentT-1,1]) == 1)
            push!(FS3exclude,f);
            CSCost += tc[f,currentT];
            txCost += tc[f,currentT];
        end
        if (getvalue(EZ[f,currentT,1]) - getvalue(EZ[f,currentT-1,1]) == 1)
            push!(FS3excludeZ,f);
            CSCost += cz[f,currentT];
            ccCost += cz[f,currentT];
        end
    end
    RSet = [];
    for f in FSM
        if (getvalue(R[f,1]) == 1)
            push!(RSet,f);
        end
    end
    return FS1exclude,FS2exclude,FS2excludeY,FS2excludeZ,FS3exclude,FS3excludeZ,RSet,CSCost,gCost,abCost,txCost,ccCost
end

function updateF(FSO1,FSO2,FSO3,FSO,capAdd,connAdd,currentT,FS1E,FS2E,FS3E,FS3EZ,LC,S,TS,tau)
    # move all the flights that have been cleared from F1 to F2
    if FS1E != []
        FSM1 = setdiff(FSO1,FS1E);
        FSM2 = union(FSO2,FS1E);
        for f in FS1E
            LC[f] = currentT+N+tau[f];
        end
    else
        FSM1 = FSO1;
        FSM2 = FSO2;
    end
    if FS2E != []
        FSM2 = setdiff(FSM2,FS2E);
        FSM = setdiff(FSO,FS2E);
    else
        FSM = FSO;
    end
    if FS3E != []
        FSM3 = setdiff(FSO3,FS3E);
        if FS3EZ != []
            FSM3 = setdiff(FSM3,FS3EZ);
        end
    else
        if FS3EZ != []
            FSM3 = setdiff(FSO3,FS3EZ);
        else
            FSM3 = FSO3;
        end
    end

    capType = readdlm(capAdd,',',header = false);
    connMat = readdlm(connAdd,',',header = false);
    connMat = round(Int64,connMat);
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
    totalCapDict = Dict(1=>6,2=>5,3=>3);
    ArrCapDict = Dict(1=>4,2=>3,3=>2);
    DeptCapDict = Dict(1=>4,2=>3,3=>2);
#    ArrCapDict = Dict();
#    DeptCapDict = Dict();
#    for i in 1:40
#        ArrCapDict[i] = round(totalCapDict[i]*60/107);
#        DeptCapDict[i] = round(totalCapDict[i]*70/107);
#    end
    capA = [];
    capD = [];
    capT = [];
    for i in capType
        push!(capA,ArrCapDict[i]);
        push!(capD,DeptCapDict[i]);
        push!(capT,totalCapDict[i]);
    end
    return FSM1,FSM2,FSM3,FSM,LC,capA,capD,capT,connMat
end

function Main_Stoch(ArrAdd,DeptAdd,capAdd,N,outArrAdd,outDeptAdd,connAdd)
    FSM1,FSM2,FSM3,FSM,AFlightID,DFlightID,LC,S,TS,tau,capA,capD,capT,T,M,connMat = solveStochPre(N,ArrAdd,DeptAdd,capAdd,connAdd);
    F = maximum(FSM);
    F3 = maximum(FSM3);
    # obtain the output
    Xtime = zeros(F);
    Ytime = zeros(F);
    Ltime = zeros(F);
    Dtime = zeros(F);
    Ztime = zeros(F);
    Etime = zeros(F3);
    EZtime = zeros(F3);
    SArray = zeros(F);
    LCArray = zeros(F);
    RArray = zeros(F);

    CSCost = zeros(T);
    CSgdpCost = zeros(T);
    CSabCost = zeros(T);
    CStxCost = zeros(T);
    CSccCost = zeros(T);
    for f in FSM
        SArray[f] = S[f];
        LCArray[f] = LC[f];
    end

    for currentT in 1:T
        println(currentT);
        FS1E,FS2E,FS2EY,FS2EZ,FS3E,FS3EZ,RSet,CSCost[currentT],CSgdpCost[currentT],CSabCost[currentT],CStxCost[currentT],CSccCost[currentT] =
            solveStoch(currentT,T,N,M,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,capA,capD,capT,connMat);
        for f in FS1E
            Xtime[f] = currentT;
            Dtime[f] = currentT+N;
            Ltime[f] = currentT+N+tau[f];
        end
        for f in FS2EY
            Ytime[f] = currentT;
        end
        for f in FS2EZ
            Ztime[f] = currentT;
        end
        for f in FS3E
            Etime[f] = currentT;
        end
        for f in FS3EZ
            EZtime[f] = currentT;
        end
        if currentT < T
            capAdd = string(capAdd[1:67],string(currentT+1),".csv");
            connAdd = string(connAdd[1:70],string(currentT+1),".csv");
            FSM1,FSM2,FSM3,FSM,LC,capA,capD,capT = updateF(FSM1,FSM2,FSM3,FSM,capAdd,connAdd,currentT,FS1E,FS2E,FS3E,FS3EZ,LC,S,TS,tau);
        else
            for f in RSet
                RArray[f] = 1;
            end
        end
    end
    dfArr = DataFrame(Flight_ID = AFlightID, ID = 1:F, Clearance_Time = Xtime, Scheduled_Departure = SArray, Actual_Departure = Dtime, Scheduled_Arrival = LCArray, Actual_Arrival = Ltime, Actual_Landing = Ytime, CancelStatus = Ztime, RerouteStatus = RArray);
    dfDept = DataFrame(Flight_ID = DFlightID, ID = 1:F3, Departure_Time = Etime, CancelStatus = EZtime);
    writetable(outArrAdd,dfArr,header = true);
    writetable(outDeptAdd,dfDept,header = true);
    println("Total Cost = ",sum(CSCost))
    println("GDP Cost = ",sum(CSgdpCost))
    println("Airborne Cost = ",sum(CSabCost))
    println("Taxi-out Cost = ",sum(CStxCost))
    println("Cancellation Cost = ",sum(CSccCost))
    return CSCost,CSgdpCost,CSabCost,CStxCost,CSccCost,RArray
end

ArrAdd = "C:\\Users\\hyang\\Documents\\Air Traffic Control\\Model\\1_22\\ATL_Arr_1_22.csv";
DeptAdd = "C:\\Users\\hyang\\Documents\\Air Traffic Control\\Model\\1_22\\ATL_Dept_1_22.csv";
capAdd = "C:\\Users\\hyang\\Documents\\Air Traffic Control\\Model\\1_22\\weatherMat_1.csv";
connAdd = "C:\\Users\\hyang\\Documents\\Air Traffic Control\\Model\\1_22\\connectionMat_1.csv";
N = 4;
outAAdd = "C:\\Users\\hyang\\Documents\\Air Traffic Control\\Model\\1_22\\output_Stoch_Arrival.csv";
outDAdd = "C:\\Users\\hyang\\Documents\\Air Traffic Control\\Model\\1_22\\output_Stoch_Departure.csv";
CSCost1,CSgdpCost1,CSabCost1,CStxCost1,CSccCost1,RArray1 = Main_Stoch(ArrAdd,DeptAdd,capAdd,N,outArrAdd,outDeptAdd,connAdd);
