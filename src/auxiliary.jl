# auxiliary tools to manipulate time variables

function transTime(timeInput)
    # transform a time input from a length 2-4 string/int to a timeType variable
    if typeof(timeInput) == Int64
        tp = timeInput;
        tphr = div(tp,100);
        tpmin = tp%100;
        if (tpmin > 60) | (tphr > 24)
            error("Invalid time input");
        end
        ttp = timeType(tphr,tpmin);
        return ttp;
    elseif typeof(timeInput) == String
        tp = parse(Int,timeInput);
        tphr = div(tp,100);
        tpmin = tp%100;
        if (tpmin > 60) | (tphr > 24)
            error("Invalid time input");
        end
        ttp = timeType(tphr,tpmin);
        return ttp;
    else
        error("Invalid time format");
    end
end

function timeDiff(startT,endT)
    # by default we assume endT > startT
    startTp = startT.hr*2 + div(startT.min,30) + 1;
    endTp = endT.hr*2 + div(endT.min,30) + 1;
    if endTp < startTp
        endTp += 48;
    end
    # return the number of time periods
    return endTp - startTp + 1;
end
