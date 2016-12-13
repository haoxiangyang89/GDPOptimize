using JuMP,Distributions,Cbc;

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

function initiMain(capAddress,capProbAdd,ArrAdd,DeptAdd,N)
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
    totalT = size(capacity_info_txt)[1];
    for t = 1:totalT
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
    currentT = 1;

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

    return currentT,FSI1,FSI2,FSI3,FSI,LC,S,TS,tau,capDict,probDict,AFlightID,DFlightID,totalT
end

function genCap(mg,ct,gT,capD,probD)
    # return M sample paths
    # gT is the number of time periods simulated
    # plain MC simulation
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

function initPre(totalT,currentT,M,N,FSIP1,FSIP2,FSIP3,FSIP)
    # set up the initial values of X,Y,Z,D,E,EZ,L,H
    Xp = Dict();
    Yp = Dict();
    Zp = Dict();
    Dp = Dict();
    Ep = Dict();
    Lp = Dict();
    Hp = Dict();
    Rp = Dict();
    for i in 1:M
        for f in FSIP
            Rp[i,f] = 0;
        for t in (currentT - 1):totalT
            for f in FSIP1
                Xp[i,f,t] = 0;
                Zp[i,f,t] = 0;
                Dp[i,f,t] = 0;
                for tt in 1:(N+tau[f]-1)
                    Hp[i,f,t,tt] = 0;
            end
            for f in FSIP
                Yp[i,f,t] = 0;
                Lp[i,f,t] = 0;
            end
            for f in FSIP3
                Ep[i,f,t] = 0;
                EZp[i,f,t] = 0;
            end
        end
    end
    return Xp,Yp,Zp,Dp,Ep,EZp,Lp,Hp,Rp
end

function createTail(currentT,T,totalT,N,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,gC,aC,cC,tcC,czC,CR,vList,piList)
    # build up the problem of the last stage in SDDP
    m = Model();
    # set up the variables
    @variable(m,X[FSM1,currentT + T - 1:totalT],Bin);    # clearance
    @variable(m,D[FSM1,currentT + T - 1:totalT],Bin);    # departure
    @variable(m,Y[FSM,currentT + T - 1:totalT],Bin);     # landing
    @variable(m,Z[FSM1,currentT + T - 1:totalT],Bin);    # cancellation
    @variable(m,L[FSM,currentT + T - 1:totalT],Bin);     # arrival
    @variable(m,E[FSM3,currentT + T - 1:totalT],Bin);    # taking off
    @variable(m,EZ[FSM3,(currentT - 1):totalT],Bin);     # departure cancellation
    @variable(m,R[FSM],Bin);                             # reroute

    # set up the objective function
    rerouteCostH = @expression(m,rerouteCost,sum{R[f]*CR[f],f in FSM});
    gdpCostH = @expression(m,gdpCost,sum{sum{gC[f,t]*(D[f,t] - D[f,t-1]),t in max(S[f] - N,currentT+T):totalT},f in FSM1});
    cancelCostH = @expression(m,cancelCost,sum{sum{cC[f,t]*(Z[f,t] - Z[f,t-1]),t in (currentT+T):totalT},f in FSM1} + sum{sum{czC[f,t]*(EZ[f,t] - EZ[f,t-1]),t in (currentT+T):totalT},f in FSM3});
    airborneCostH = @expression(m,airborneCost,sum{sum{aC[f]*(L[f,t] - Y[f,t]),t in max(LC[f],currentT+T):totalT},f in FSM});
    taxiCostH = @expression(m,taxiCost,sum{sum{tcC[f,t]*(E[f,t] - E[f,t-1]),t in max(currentT+T,TS[f]):totalT},f in FSM3});
    @objective(m,Min,gdpCost+cancelCost+airborneCost+taxiCost+rerouteCostH);

    # set up the constraints
    @constraint(m,mustLand1[f in FSM1],Z[f,totalT]+Y[f,totalT]+R[f] == 1);
    @constraint(m,mustLand2[f in FSM2],Y[f,totalT]+R[f] == 1);
    @constraint(m,mustTakeoff[f in FSM3],E[f,totalT]+EZ[f] == 1);
    @constraint(m,noCancel[f in FSM1, t = (currentT+T):totalT], Z[f,t] + D[f,t] <= 1);
    @constraint(m,noCancel2[f in FSM3, t in (currentT+T):totalT], EZ[f,t] + E[f,t] <= 1);
    @constraint(m,landAfter[f in FSM, t = (currentT+T):totalT], Y[f,t] <= L[f,t]);
    @constraint(m,planDept1[f in FSM1, t in (currentT+T):totalT;t - currentT - T < N], D[f,t] == 0);                                               # RHS change pending
    @constraint(m,planDept2[f in FSM1, t in (currentT+T):totalT;t - currentT - T >= N], D[f,t] == X[f,t-N]);
    @constraint(m,planLand1[f in FSM,t in (currentT+T):totalT;t - currentT - t < tau[f]], L[f,t] == 0);                                                    # RHS change pending
    @constraint(m,planLand2[f in FSM,t in (currentT+T):totalT;t - currentT - t >= tau[f]], L[f,t] == D[f,t-tau[f]]);
    @constraint(m,capArr[t in (currentT+T):totalT], sum{Y[f,t] - Y[f,t-1],f in FSM} <= 2000);        # RHS change pending
    @constraint(m,capDept[t in (currentT+T):totalT], sum{E[f,t] - E[f,t-1],f in FSM3} <= 2000);      # RHS change pending
    @constraint(m,capTot[t in (currentT+T):totalT], sum{E[f,t] - E[f,t-1],f in FSM3} + sum{Y[f,t] - Y[f,t-1],f in FSM} <= 2000);      # RHS change pending
    @constraint(m,propX[f in FSM1, t = (currentT+T):totalT], X[f,t] >= X[f,t-1]);
    @constraint(m,propY[f in FSM, t = (currentT+T):totalT], Y[f,t] >= Y[f,t-1]);
    @constraint(m,propZ[f in FSM1, t = (currentT+T):totalT], Z[f,t] >= Z[f,t-1]);
    @constraint(m,propE[f in FSM3, t = (currentT+T):totalT], E[f,t] >= E[f,t-1]);
    @constraint(m,propEZ[f in FSM3, t = (currentT+T):totalT], E[f,t] >= E[f,t-1]);

    @constraint(m,F1noDept[f in FSM1, t in (currentT+T):min(currentT+T+N-1,totalT)], D[f,t] == 0);
    @constraint(m,F1noArr[f in FSM1, t in (currentT+T):min(currentT+T+N+tau[f]-1,totalT)], L[f,t] == 0);
    @constraint(m,F2Arr[f in FSM2, t = max(LC[f],currentT+T):totalT], L[f,t] == 1);
    @constraint(m,F2noArr[f in FSM2, t = (currentT+T-1):(LC[f]-1)], L[f,t] == 0);
    @constraint(m,noTakeoff[f in FSM1, t = (currentT+T):S[f]-1], D[f,t] == 0);
    @constraint(m,F3noDept[f in FSM3,t in (currentT+T):totalT;t<TS[f]],E[f,t] == 0);

    @constraint(m, initX[f in FSM1], X[f,currentT + T - 1] == 0);                          # RHS change pending
    @constraint(m, initY[f in FSM], Y[f,currentT + T - 1] == 0);                           # RHS change pending
    @constraint(m, initZ[f in FSM1], Z[f,currentT + T - 1] == 0);                          # RHS change pending
    @constraint(m, initE[f in FSM3], E[f,currentT + T - 1] == 0);
    @constraint(m, initEZ[f in FSM3], EZ[f,currentT + T - 1] == 0);                        # RHS change pending

    return m
end

function createStream(t,T,totalT,N,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,gC,aC,cC,tcC,CR,vList,piList)
    # with a tail
    mo = Model();
    # set up the variables
    @variable(mo,X[FSM1],Bin);    # clearance
    @variable(mo,D[FSM1],Bin);    # departure
    @variable(mo,Y[FSM],Bin);     # landing
    @variable(mo,Z[FSM1],Bin);    # cancellation
    @variable(mo,L[FSM],Bin);     # arrival
    @variable(mo,E[FSM3],Bin);    # taking off
    @variable(mo,θ >= 0);
    for f in FSM1
        @variable(mo,H[f,1:(N+tau[f]-1)],Bin);
    end

    # set up the objective function
    gdpCostH = @expression(mo,gdpCost,sum{gC[f,t]*D[f],f in FSM1});
    cancelCostH = @expression(mo,cancelCost,sum{cC[f,t]*Z[f],f in FSM1} + sum{czC[f,t]*EZ[f],f in FSM3});
    airborneCostH = @expression(mo,airborneCost,sum{aC[f]*(L[f] - Y[f]),f in FSM});
    taxiCostH = @expression(mo,taxiCost,sum{tcC[f,t]*E[f],f in FSM3});
    @objective(mo,Min,gdpCost+cancelCost+airborneCost+taxiCost+θ);

    @constraint(mo,noCancel[f in FSM1],Z[f]+D[f] <= 1);
    @constraint(mo,landAfter[f in FSM],Y[f] <= L[f]);
    @constraint(mo,noTakeoff[f in FSM1;t <= S[f]-1],D[f] == 0);
    @constraint(mo,planLand[f in FSM1;t >= tau[f]+1],L[f] == 0);    # RHS change pending
    @constraint(mo,planDept[f in FSM1;t >= N+1],D[f] == 0);    # RHS change pending
    @constraint(mo,recHist[f in FSM1,t in 2:(N+tau[f]-1)],H[f,t] == 0);   # RHS change pending
    @constraint(mo,recHistC[f in FSM1], H[f,1] == X[f]);
    @constraint(mo,F2Arr[f in FSM2;t >= LC[f]],L[f] == 1);
    @constraint(mo,F2noArr[f in FSM2;t < LC[f]],L[f] == 0);
    @constraint(mo,F3noDept[f in FSM3;t<TS[f]],E[f] == 0);
    @constraint(mo,capArr,sum{Y[f],f in FSM} <= 2000);    # RHS change pending
    @constraint(mo,capDept,sum{E[f], f in FSM3} <= 2000); # RHS change pending
    @constraint(mo,capTot,sum{Y[f],f in FSM} + sum{E[f], f in FSM3} <= 2000);      # RHS change pending
    @constraint(mo,propX[f in FSM1],X[f] >= 0);     # RHS change pending
    @constraint(mo,propY[f in FSM],Y[f] >= 0);      # RHS change pending
    @constraint(mo,propZ[f in FSM1],Z[f] >= 0);     # RHS change pending
    @constraint(mo,propE[f in FSM3],E[f] >= 0);     # RHS change pending

    @constraint(mo,thetaCon[l in keys(vList[t])],θ >= vList[t][l]+sum{piList[f,t,1][l]*X[f]+piList[f,t,3][l]*Z[f]+piList[f,t,4][l]*H[f,N-1]+piList[f,t,5][l]*H[f,N+tau[f]-1]+
        sum{piList[f,t,6+u][l],u in 1:(N+tau[f]-2)},f in FSM1}+sum{piList[f,t,2][l]*Y[f],f in FSM}+sum{piList[f,t,6][l]*E[f],f in FSM3});

    return mo
end

function createEnd(t,T,totalT,N,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,gC,aC,cC,tcC,CR,vList,piList)
    # with no tail
    m = Model();
    # set up the variables
    @variable(m,X[FSM1],Bin);    # clearance
    @variable(m,D[FSM1],Bin);    # departure
    @variable(m,Y[FSM],Bin);     # landing
    @variable(m,Z[FSM1],Bin);    # cancellation
    @variable(m,L[FSM],Bin);     # arrival
    @variable(m,E[FSM3],Bin);    # taking off
    for f in FSM1
        @variable(mo,H[f,1:(N+tau[f]-1)],Bin);
    end

    @variable(m,R1[FSM],Bin);    # emergency outlet of landing
    @variable(m,R2[FSM3],Bin);   # emergency outlet of taking off
    addCost1H = @expression(m,addCost1,sum{R1[f]*CR,f in FSM});
    addCost2H = @expression(m,addCost2,sum{R2[f]*CR,f in FSM3});
    @constraint(m,termCond1[f in FSM],Z[f]+Y[f]+R1[f] == 1);
    @constraint(m,termCond2[f in FSM],E[f]+R2[f] == 1);

    # set up the objective function
    gdpCostH = @expression(m,gdpCost,sum{g[f,t]*D[f],f in FSM1});
    cancelCostH = @expression(m,cancelCost,sum{c[f,t]*Z[f],f in FSM1});
    airborneCostH = @expression(m,airborneCost,sum{a[f]*(L[f] - Y[f]),f in FSM});
    taxiCostH = @expression(m,taxiCost,sum{tc[f]*E[f],f in FSM3});
    @objective(m,Min,gdpCost+cancelCost+airborneCost+taxiCost+addCost1+addCost2);

    @constraint(m,noCancel[f in FSM1],Z[f]+D[f] <= 1);
    @constraint(m,landAfter[f in FSM],Y[f] <= L[f]);
    @constraint(m,noTakeoff[f in FSM1;t <= S[f]-1],D[f] == 0);
    @constraint(m,planLand[f in FSM1;t >= tau[f]+1],L[f] == 0);    # RHS change pending
    @constraint(m,planDept[f in FSM1;t >= N+1],D[f] == 0);    # RHS change pending
    @constraint(m,F2Arr[f in FSM2;t >= LC[f]],L[f] == 1);
    @constraint(mo,recHist[f in FSM1,t in 2:(N+tau[f]-1)],H[f,t] == 0);   # RHS change pending
    @constraint(mo,recHistC[f in FSM1], H[f,1] == X[f]);
    @constraint(m,F2noArr[f in FSM2;t < LC[f]],L[f] == 0);
    @constraint(m,F3noDept[f in FSM3;t<TS[f]],E[f] == 0);
    @constraint(m,capArr,sum{Y[f],f in FSM} <= 2000);    # RHS change pending
    @constraint(m,capDept,sum{E[f], f in FSM3} <= 2000); # RHS change pending
    @constraint(m,capTot,sum{Y[f],f in FSM} + sum{E[f], f in FSM3} <= 2000);      # RHS change pending
    @constraint(m,propX[f in FSM1],X[f] >= 0);     # RHS change pending
    @constraint(m,propY[f in FSM],Y[f] >= 0);      # RHS change pending
    @constraint(m,propZ[f in FSM1],Z[f] >= 0);     # RHS change pending
    @constraint(m,propE[f in FSM3],E[f] >= 0);     # RHS change pending

    @constraint(mo,thetaCon[l in keys(vList[t])],θ >= vList[t][l]+sum{piList[f,t,1][l]*X[f]+piList[f,t,3][l]*Z[f]+piList[f,t,4][l]*H[f,N-1]+piList[f,t,5][l]*H[f,N+tau[f]-1]+
        sum{piList[f,t,6+u][l],u in 1:(N+tau[f]-2)},f in FSM1}+sum{piList[f,t,2][l]*Y[f],f in FSM}+sum{piList[f,t,6][l]*E[f],f in FSM3});

    return m
end

function updateUB(X,Y,Z,D,E,L,mUB,FSUB1,FSUB2,FSUB3,FSUB,LC,S,TS,tau,capDict,probDict,gUB,aUB,cUB,tcUB)
    # this is the function that calculates the upper bound in an SDDP iteration
end

function solveLagrangian(Xsol,Ysol,Zsol,Esol,Dsol,Lsol,Hsol,t,k,j,N,FS1,FS2,FS3,FS,LC,S,TS,tau,CA,CD,CT,g,a,c,tc)
    # set up the dual variable
    pi = Dict();
    for f in FS1
        for i in 1:4+N+tau[f]
            pi[f,i] = 0;
        end
    end
    for f in FS2
        pi[f,2] = 0;
    end
    for f in FS3
        pi[f,6] = 0;
    end

    while criteriaMet
        m = Model();

        @variable(m,X[FS1],Bin);
        @variable(m,Y[FS],Bin);
        @variable(m,Z[FS1],Bin);
        @variable(m,D[FS1],Bin);
        @variable(m,L[FS],Bin);
        @variable(m,E[FS3],Bin);
        @variable(m,H[FS1,1:(N+tau[f]-1)],Bin);
        @variable(m,0<=sX[FS1]<=1);
        @variable(m,0<=sY[FS]<=1);
        @variable(m,0<=sZ[FS1]<=1);
        @variable(m,0<=sD[FS1]<=1);
        @variable(m,0<=sL[FS]<=1);
        @variable(m,0<=sE[FS3]<=1);
        @variable(m,0<=sH[FS1,2:(N+tau[f]-1)]<=1);

        @objective(m,Min,sum{g[f,t]*D[f,t]+c[f,t]*Z[f,t]-pi[f,1]*(sX[f] - Xsol[k,f,t-1])-pi[f,3]*(sZ[f] - Zsol[k,f,t-1])-
            -pi[f,4]*(sD[f]-Hsol[k,f,t-1,N-1])-pi[f,5]*(sL[f]-Hsol[k,f,t-1,N+tau[f]-1])-sum{pi[f,u+5](sH[f,u] - Hsol[k,f,t-1,u-1]),u in 2:(N+tau[f]-1)},f in FS1}
            +sum{pi[f,2]*(sY[f]-Ysol[k,f,t-1]),f in FS}+sum{pi[f,6]*(SE[f]-Esol[k,f,t-1]),f in FS3}+θ);

        @constraint(m,noCancel[f in FS1],Z[f] + D[f] <= 1);
        @constraint(m,landAfter[f in FS],Y[f] <= L[f]);
        @constraint(m,noTakeoff[f in FS1;t <= S[f]-1],D[f] == 0);
        @constraint(m,planLand[f in FS1;t >= tau[f]+1],L[f] == sL[f]);
        @constraint(m,planDept[f in FS1;t >= N+1],D[f] == sD[f]);
        @constraint(m,F2Arr[f in FS2;t >= LC[f]],L[f] == 1);
        @constraint(mo,recHist[f in FS1,t in 2:(N+tau[f]-1)],H[f,t] == sH[f,t]);
        @constraint(mo,recHistC[f in FS1], H[f,1] == X[f]);
        @constraint(m,F2noArr[f in FS2;t < LC[f]],L[f] == 0);
        @constraint(m,F3noDept[f in FS3;t<TS[f]],E[f] == 0);
        @constraint(m,capArr,sum{Y[f],f in FS} <= CA);
        @constraint(m,capDept,sum{E[f], f in FS3} <= CD);
        @constraint(m,capTot,sum{Y[f],f in FS} + sum{E[f], f in FS3} <= CT);
        @constraint(m,propX[f in FS1],X[f] >= sX[f]);
        @constraint(m,propY[f in FS],Y[f] >= sY[f]);
        @constraint(m,propZ[f in FS1],Z[f] >= sZ[f]);
        @constraint(m,propE[f in FS3],E[f] >= sE[f]);

        # add the cuts already generated for theta!!!

        solve(m);

        # update the dual multiplier pi
        # check the stopping criteria
    end
    v = getobjectivevalue(m);
    for f in FS1
        v += pi[f,1]*Xsol[k,f,t-1];
        v += pi[f,3]*Zsol[k,f,t-1];
        v += pi[f,4]*Hsol[k,f,t-1,N-1];
        v += pi[f,5]*Hsol[k,f,t-1,N+tau[f]-1];
    end
    for f in FS
        v += pi[f,2]*Ysol[k,f,t-1];
    end
    for f in FS3
        v += pi[f,6]*Esol[k,af,t-1];
    end
    return v,pi
end

function updateCut(t,Ome,probDict,probDict,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,vList,piList,vLR,πLR)
  #!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    # append the Lagrangian cut to the list
    if !(t in keys(vList))
        vList[t] = [];
        for f in
    end
    vsum = 0;
    pisum = Dict();
    for ome in 1:Ome
        vsum += vLR[ome]*probDict[t][ome];
    end
    push!(vList[t],vsum);
end

function getCapDict(M,dT,dA,dD)
    totalCapDict = Dict();
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
    ArrCapDict = Dict();
    DeptCapDict = Dict();
    for i in 1:M
        totalCapDict[i] = dT[i];
        ArrCapDict[i] = dA[i];
        DeptCapDict[i] = dD[i];
#        ArrCapDict[i] = round(totalCapDict[i]*60/107);
#        DeptCapDict[i] = round(totalCapDict[i]*70/107);
    end
    return totalCapDict,ArrCapDict,DeptCapDict
end

function Main(totalT,T,currentT,N,M,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,capDict,probDict)
    # this is the function that carries out the SDDP and output the solution

    # one to one mapping between scenario and capacity
    totalCapDict,ArrCapDict,DeptCapDict = getCapDict(3,[6,5,3],[4,3,2],[4,3,2]);

    # set up the default solver as CbcSolver
    #solver = CbcSolver(seconds = 9000);
    solver = CplexSolver();
    ub = 10000000000;
    lb = 0;
    iterNo = 0;
    ϵ = 0.05;
    # generate costs based on their scheduled departure
    gM,aM,cM,tcM = generateCost(currentT,totalT,LC,S,TS,FSM1,FSM2,FSM3,FSM);
    vList = [];
    piList = [];

    while ((ub - lb)/lb >= ϵ) || (iterNo <= 500)
        # sample M scenarios
        iterNo = iterNo + 1;
        if currentT + T - 1 <= totalT
            scenList = genCap(M,currentT,T,capDict,probDict);
            tailList = Dict();
            for t in (currentT + T):totalT
                tailList[t] = indmax(probDict[t]);
            end
        else
            scenList = genCap(M,currentT,totalT - currentT + 1,capDict,probDict);
        end

        # forward step
        Xpre,Ypre,Zpre,Dpre,Epre,Lpre,Hpre = initPre(totalT,currentT,M,N,FSM1,FSM2,FSM3,FSM);
        for k = 1:M
            if currentT + T - 1 <= totalT
                endT = currentT + T - 1;
                for t = currentT:endT
                    # create the template problem for each time period
                    m = createStream(t,T,totalT,N,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,gM,aM,cM,tcM,1000);

                    # change RHS for each time period
                    # change the RHS for capacity constraints
                    JuMP.setRHS(m.conDict[:capArr],ArrCapDict[scenList[k,t]]);
                    JuMP.setRHS(m.conDict[:capDept],DeptCapDict[scenList[k,t]]);
                    JuMP.setRHS(m.conDict[:capTot],totalCapDict[scenList[k,t]]);
                    if t >= N+1
                        for f in FSM1
                            JuMP.setRHS(m.conDict[:planDept][f],Xpre[k,f,t - N]);
                        end
                    end
                    for f in FSM1
                        if t >= tau[f]
                            JuMP.setRHS(m.conDict[:planLand][f],Dpre[k,f,t - tau[f]]);
                        end
                    end
                    for f in FSM1
                        JuMP.setRHS(m.conDict[:propX][f],Xpre[k,f,t - 1]);
                        JuMP.setRHS(m.conDict[:propZ][f],Zpre[k,f,t - 1]);
                    end
                    for f in FSM
                        JuMP.setRHS(m.conDict[:propY][f],Ypre[k,f,t - 1]);
                    end
                    for f in FSM3
                        JuMP.setRHS(m.conDict[:propE][f],Epre[k,f,t - 1]);
                    end

                    # solve the problem
                    solve(m);

                    # record each scenario stream's optimal value and optimal solutions
                    for f in FSM1
                        Xpre[k,f,t] = getvalue(m.varDict[:X][f]);
                        Zpre[k,f,t] = getvalue(m.varDict[:Z][f]);
                        Dpre[k,f,t] = getvalue(m.varDict[:D][f]);
                    end
                    for f in FSM
                        Ypre[k,f,t] = getvalue(m.varDict[:Y][f]);
                        Lpre[k,f,t] = getvalue(m.varDict[:L][f]);
                    end
                    for f in FSM3
                        Epre[k,f,t] = getvalue(m.varDict[:E][f]);
                    end
                end

                # change RHS for the tail problem
                mt = createTail(currentT,T,totalT,N,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,gM,aM,cM,tcM,1000);
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
                    if t < endT
                        m = createStream(t,T,totalT,N,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,gM,aM,cM,tcM,1000);
                    else
                        m = createEnd(t,T,totalT,N,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,gM,aM,cM,tcM,1000);
                    # change RHS for each time period
                    # change the RHS for capacity constraints
                    JuMP.setRHS(m.conDict[:capArr],ArrCapDict[scenList[k,t]]);
                    JuMP.setRHS(m.conDict[:capDept],DeptCapDict[scenList[k,t]]);
                    JuMP.setRHS(m.conDict[:capTot],totalCapDict[scenList[k,t]]);
                    if t >= N
                        for f in FSM1
                            JuMP.setRHS(m.conDict[:planDept][f],Xpre[k,f,t - N]);
                        end
                    end
                    for f in FSM1
                        if t >= tau[f]
                            JuMP.setRHS(m.conDict[:planLand][f],Dpre[k,f,t - tau[f]]);
                        end
                    end
                    for f in FSM1
                        JuMP.setRHS(m.conDict[:propX][f],Xpre[k,f,t - 1]);
                        JuMP.setRHS(m.conDict[:propZ][f],Zpre[k,f,t - 1]);
                    end
                    for f in FSM
                        JuMP.setRHS(m.conDict[:propY][f],Ypre[k,f,t - 1]);
                    end
                    for f in FSM3
                        JuMP.setRHS(m.conDict[:propE][f],Epre[k,f,t - 1]);
                    end

                    # solve the problem
                    solve(m);

                    # record each scenario stream's optimal value and optimal solutions
                    for f in FSM1
                        Xpre[k,f,t] = getvalue(m.varDict[:X][f]);
                        Zpre[k,f,t] = getvalue(m.varDict[:Z][f]);
                        Dpre[k,f,t] = getvalue(m.varDict[:D][f]);
                    end
                    for f in FSM
                        Ypre[k,f,t] = getvalue(m.varDict[:Y][f]);
                        Lpre[k,f,t] = getvalue(m.varDict[:L][f]);
                    end
                    for f in FSM3
                        Epre[k,f,t] = getvalue(m.varDict[:E][f]);
                    end
                end
            end
        end

        # when a certain criterion is met (every 10 iteration), update the upperbound with 50 streams
        if mod(iterNo,10) == 0
            M1 = 50;
            ub = updateUB(M1,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,capDict,probDict,gM,aM,cM,tcM);
        end

        # backward step
        for t = T:-1:currentT
            for k = 1:M
                vLR = Dict();
                πLR = Dict();
                for j = 1:length(probDict[t])
                    # solve the relaxation to generate cuts
                    CA = ArrCapDict[probDict[j]];
                    CD = DeptCapDict[probDict[j]];
                    CT = totalCapDict[probDict[j]];
                    vLR[j],πLR[j] = solveLagrangian(Xpre,Ypre,Zpre,Epre,Dpre,Lpre,Hpre,t,k,j,N,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,CA,CD,CT,gM,aM,cM,tcM);
                end
                # update the problem with generated cuts
                updateCut(t,length(probDict[t]),probDict,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,vList,piList,vLR,πLR);
            end
        end

        # update the lower bound
        m = createStream(currentT,T,totalT,N,FSM1,FSM2,FSM3,FSM,LC,S,TS,tau,gM,aM,cM,tcM,1000);
        solve(m);
        lb = min(getobjectivevalue(m),lb);
    end
    return Xpre,Ypre,Zpre,Epre,Dpre,Lpre
end

function updateSet(totalT,currentT,FSU1,FSU2,FSU3,FSU,X,Y,Z,D,L,E,capAddress,capProbAdd)
    # this is the function that updates the set for the next time period in the horizon
end
