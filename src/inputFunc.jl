# This is the script of functions to handle the input process

# input the random capacity information
function capInput(T,capAddress,capProbAdd)
    # create a dictionary to store the capacity information
    capD = Dict();
    # Given an address of csv file of the following information
    # First row: the number of time periods T
    # The following T rows: the first column shows the index of the time period and
    #   starting from the second column shows the predicted scenario/its probability
    capacity_info_txt = readdlm(capAddress,',',header = false);
    capacity_prob_txt = readdlm(capProbAdd,',',header = false);
    # the first column contains the time period, the following columns are the possible capacity
    # transform the input raw data into a capData variable
    for t = 1:T
        scenList = [];
        capDict = Dict();
        probDict = Dict();
        scenCounter = 0;
        for j in 2:length(capacity_info_txt[t,:])
            if capacity_info_txt[t,j] != ""
                scenCounter += 1;
                push!(scenList,scenCounter);
                capDict[scenCounter] = capacity_info_txt[t,j];
                probDict[scenCounter] = capacity_prob_txt[t,j];
            end
        end

        # fill the data in the capD
        capD[t] = capData(scenList,capDict,probDict);
    end

    return capD;
end

# input the arrival information
function arrInput(T,startT,endT,ArrAdd,N)
    # read in the original arrival flight schedule
    Arr_info_txt,title = readdlm(ArrAdd,',',header = true);
    # obtain the index of carrier ID, flight number, departure time, arrival time and elapsed time
    flCarrInd,flNoInd,rawDeptInd,rawArrInd,rawElapseInd = indexin(["UNIQUE_CARRIER","FL_NUM","CRS_DEP_TIME","CRS_ARR_TIME","CRS_ELAPSED_TIME"],title);
    lF = size(Arr_info_txt)[1];
    F1 = [];
    F2 = [];
    arrInfo = Dict();
    counter = 0;

    for i in 1:lF
        # for each row of arrival information data:
        # obtain the flight ID
        flightID = string(Arr_info_txt[i,flCarrInd],"_",Arr_info_txt[i,flNoInd]);
        F1Ind = true;
        F2Ind = false;

        # obtain the raw arrival/elapsed time
        rawArr = Arr_info_txt[i,rawArrInd];
        rawElapse = Arr_info_txt[i,rawElapseInd];
        if rawElapse >= 240
            F2Ind = true;
        end

        # obtain LC: arrival time, S: departure from origin time, τ: elapseTime
        # 400 is the first time period
        if rawArr >= startT.hr*100 + startT.min
            LC = Int64(div(rawArr - (startT.hr*100 + startT.min),100) * 2 + round(mod(rawArr - (startT.hr*100 + startT.min),100)/30) + 1);
        else
            LC = Int64(div(rawArr + 2400 - (startT.hr*100 + startT.min),100) * 2 + round(mod(rawArr + 2400 - (startT.hr*100 + startT.min),100)/30) + 1);
        end

        if LC <= T
            τ = Int64(round(rawElapse/30));
            S = Int64(LC - τ);
            if S <= N
                # if the departure is outside the planning horizon, mark the flight as exempted
                F2Ind = true;
            end

            if F1Ind
                counter += 1;
                arrInfo[counter] = faData(flightID,LC,τ,S);
                if F2Ind
                # if it is an exempted flight
                    push!(F2,counter);
                else
                # if it not an exempted flight
                    push!(F1,counter);
                end
            end
        end
    end

    return F1,F2,arrInfo;
end

# input the departure information
function deptInput(T,startT,endT,DeptAdd)
    # read in the original departure flight schedule
    Dept_info_txt,title = readdlm(DeptAdd,',',header = true);
    lF = size(Dept_info_txt)[1];
    flCarrInd,flNoInd,rawDeptInd,rawArrInd,rawElapseInd = indexin(["UNIQUE_CARRIER","FL_NUM","CRS_DEP_TIME","CRS_ARR_TIME","CRS_ELAPSED_TIME"],title);
    F3 = [];
    deptInfo = Dict();
    counter = 0;

    for i in 1:lF
        # for each row of departure information data:
        # obtain the flight ID
        flightID = string(Dept_info_txt[i,flCarrInd],"_",Dept_info_txt[i,flNoInd]);

        # obtain the raw departure time
        rawDept = Dept_info_txt[i,rawDeptInd];

        if rawDept >= startT.hr*100 + startT.min
            TS = Int64(div(rawDept - (startT.hr*100 + startT.min),100) * 2 + round(mod(rawDept - (startT.hr*100 + startT.min),100)/30) + 1);
        else
            TS = Int64(div(rawDept + 2400 - (startT.hr*100 + startT.min),100) * 2 + round(mod(rawDept + 2400 - (startT.hr*100 + startT.min),100)/30) + 1);
        end
        if TS <= T
            counter += 1;
            push!(F3,counter);
            deptInfo[counter] = fdData(flightID,TS);
        end
    end

    return F3,deptInfo;
end

function arrdeptInput(T,startT,endT,ArrAdd,DeptAdd,N)
    # execute the input process of arrival and departure data
    F1,F2,arrInfo = arrInput(T,startT,endT,ArrAdd,N);
    F3,deptInfo = deptInput(T,startT,endT,DeptAdd);
    flightD = fsData(F1,F2,F3,arrInfo,deptInfo);
    return flightD;
end

# input the cost information
# This is an arbitrary way to generate a cost. We need to update this using a valid cost generation method!!!!
function costInput(T,flightD)
    # gc: ground delay costs, ac: airborne costs
    # zc: cancellation costs, tc: taxi costs, rc: recourse feasibility penalty
    gc = Dict();    # specific for F1
    ac = 5.0;
    zc = 20.0;
    tc = Dict();    # specific for F3
    rc = 40.0;

    for t in 1:T
        # for each of the arrival flight, generate a ground delay cost
        for f in flightD.S1
            if t > flightD.arrInfo[f].S
                gc[f,t] = 1.35^(t - flightD.arrInfo[f].S);
            else
                gc[f,t] = 0;
            end
        end

        # for each of the departure flight, generate a taxi cost
        for f in flightD.S3
            if t > flightD.deptInfo[f].TS
                tc[f,t] = 1.5^(t - flightD.deptInfo[f].TS);
            else
                tc[f,t] = 0;
            end
        end
    end

    costD = costData(gc,ac,zc,tc,rc);

    return costD;
end
