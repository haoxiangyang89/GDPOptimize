# -*- coding: utf-8 -*-
"""
Created on Tue Aug 23 13:15:06 2016

@author: hyang
"""
import re
import csv
import numpy
import datetime
import pytz
from scipy.sparse import coo_matrix

def dbDatetimeConvert(dbstring):
    dbList = dbstring.split(" ")
    dbDate = dbList[0]
    dbTime = dbList[1]
    dbDateList = dbDate.split("-")
    dbTimeList = dbTime.split(":")
    return datetime.datetime(int(dbDateList[0]),int(dbDateList[1]),int(dbDateList[2]),int(dbTimeList[0]),int(dbTimeList[1]),int(dbTimeList[2]))

# read in raw TAF data for a day
def readTAF(TAFstring,ICAO,issT,startT,endT,txtEnc,windEnc,catEnc,M1,M2,M3,localTZ = 'US/Eastern'):
    # set up the local time zone
    local_tz = pytz.timezone(localTZ)    
    
    # prespecify the weather categories
    weatherList = ["+","-","VC","MI","PR","BC","DR","BL","SH","TS","FZ","DZ","RA","SN",\
                    "SG","IC","PL","GR","GS","UP","BR","FG","FU","VA","DU","SA","HZ","PY",\
                    "PO","SQ","FC","SS"]
    tafPredictor = {}
    
    # input the TAF data from a string
    plainTXT = re.sub('\s+', ' ', TAFstring).strip()
    plainTXT = plainTXT[:-1]
    # obtain a list of elements in an entry of TAF
    itemList = plainTXT.split(" ")
    
    timeCheck = {}
    # it is a TAF entry
    if itemList[0] == ICAO:
        startEnt = 1
    else:
        startEnt = 2
        if itemList[1] == 'AMD':
            startEnt = 3
        
    weatherDict = {}
    for iKey in weatherList:
        weatherDict[iKey] = 0
        
    # append the issuance date time
    fmtimePt = []
    dayIss = int(itemList[startEnt][:2])
    hourIss = int(itemList[startEnt][-5:-3])
    minIss = int(itemList[startEnt][-3:-1])
    issuedTime = issT
    if not(issuedTime.day == dayIss and issuedTime.hour == hourIss and issuedTime.minute == minIss):
        raise ValueError("Please type in the issuance time which matches the TAF entry")
    
    timestamp = datetime.datetime(issuedTime.year,issuedTime.month,dayIss,hourIss) + datetime.timedelta(1/24.0)
    fmtimePt.append(timestamp)
    
    validList = itemList[startEnt+1].split("/")
    validToDay = int(validList[1][:2])
    validToHr = int(validList[1][2:])
    if validToDay < timestamp.day:
        validToMon = timestamp.month + 1
        if validToMon > 12:
            validToMon = 1
            validToYr = timestamp.year + 1
        else:
            validToYr = timestamp.year
    else:
        validToMon = timestamp.month
        validToYr = timestamp.year
    validToMin = 0
    
    startEnt += 2
    eventPt = [startEnt - 1]
    typePt = [0]
    
    # obtain each time point: FM/TEMPO/PROB
    for i in range(startEnt,len(itemList)):
        if (itemList[i][:2] == "FM"):
            tpDay = int(itemList[i][2:4])
            tpHr = int(itemList[i][4:6])
            tpMin = int(itemList[i][6:8])
            if tpDay < timestamp.day:
                tpMon = timestamp.month + 1
                if tpMon > 12:
                    tpMon = 1
                    tpYr = timestamp.year + 1
                else:
                    tpYr = timestamp.year
            else:
                tpMon = timestamp.month
                tpYr = timestamp.year
            timeFM = datetime.datetime(tpYr,tpMon,tpDay,tpHr,tpMin)
            fmtimePt.append(timeFM)
            eventPt.append(i)
            typePt.append(0)
        elif (itemList[i] == "TEMPO"):
            eventPt.append(i)
            typePt.append(1)
        elif (itemList[i] == "BECMG"):
            eventPt.append(i)
            typePt.append(2)
        elif (itemList[i][:4] == "PROB"):
            eventPt.append(i)
            typePt.append(3)
    
    eventPt.append(len(itemList))
    typePt.append(4)
            
    # examine each segment
    fmCounter = 0
    default_ceiling = 120
    for i in range(len(eventPt) - 1):
        currentCeiling = 99999
        # obtain the starting and ending time
        if typePt[i] == 0:
            validFromYr = fmtimePt[fmCounter].year
            validFromMon = fmtimePt[fmCounter].month
            validFromDay = fmtimePt[fmCounter].day
            validFromHr = fmtimePt[fmCounter].hour
            validFromMin = fmtimePt[fmCounter].minute
            
            fmCounter += 1
            if fmCounter < len(fmtimePt):
                validToYrK = fmtimePt[fmCounter].year
                validToMonK = fmtimePt[fmCounter].month
                validToDayK = fmtimePt[fmCounter].day
                validToHrK = fmtimePt[fmCounter].hour
                validToMinK = fmtimePt[fmCounter].minute
            else:
                validToYrK = validToYr
                validToMonK = validToMon
                validToDayK = validToDay
                validToHrK = validToHr
                validToMinK = validToMin
            sSen = eventPt[i]+1
            eSen = eventPt[i+1]
            visibility = 10
        else:
            tempTList = itemList[eventPt[i]+1].split("/")
            validFromDay = int(tempTList[0][:2])
            validFromHr = int(tempTList[0][2:])
            validFromMin = 0
            if validFromDay < timestamp.day:
                validFromMon = timestamp.month + 1
                if validFromMon > 12:
                    validFromMon = 1
                    validFromYr = timestamp.year + 1
                else:
                    validFromYr = timestamp.year
            else:
                validFromMon = timestamp.month
                validFromYr = timestamp.year
            validToDayK = int(tempTList[1][:2])
            validToHrK = int(tempTList[1][2:])
            validToMinK = 0
            if validToDayK < timestamp.day:
                validToMonK = timestamp.month + 1
                if validToMonK > 12:
                    validToMonK = 1
                    validToYrK = timestamp.year + 1
                else:
                    validToYrK = timestamp.year
            else:
                validToMonK = timestamp.month
                validToYrK = timestamp.year
            sSen = eventPt[i]+2
            eSen = eventPt[i+1]
            
        plusIND = 0
        minusIND = 0
        snowIND = 0
        rainIND = 0
        thunderIND = 0
        icepalIND = 0
        hailIND = 0
        mistIND = 0
        hazeIND = 0
        fogIND = 0
        # parse visibility, ceiling and weather information
        for word in itemList[sSen:eSen]:
            #check if the current index shows the wind speed
            if word[-2:] == "KT":
                angle = word[:3]
                speed = int(word[-4:-2])
                if word.find("G") == -1:
                    gust = 0
                    gustSpeed = -1
                else:
                    gust = 1
                    gustSpeed = int(word[word.find("G")-2:word.find("G")])
                    
            # check if the current index shows the visibility
            if word[-2:] == "SM":
                if word[0] == "P":
                    visibility = 10
                else:
                    visibility = eval(word[:-2])
            
            # check if the current index shows the cloud information
            if ("BKN" in word) or ("OVC" in word) or ("VV" in word):
                currentCeiling = min(currentCeiling,int(re.findall("[0-9]+",word)[0]))
            else:
                # check if the current index shows the certain type of weather
                if "+" in word:
                    plusIND = 1
                if "-" in word:
                    minusIND = 1
                # if snow appears
                if "SN" in word:
                    snowIND = 1
                # if rain or drizzle appears
                if ("RA" in word) or ("DZ" in word):
                    rainIND = 1
                # if thunderstorm appears
                if ("TS" in word):
                    thunderIND = 1
                # if freezing or ice pallet appears
                if ("FZ" in word) or ("PL" in word):
                    icepalIND = 1
                # if hail appears
                if ("GR" in word) or ("GS" in word):
                    hailIND = 1
                # if mist appears
                if ("BR" in word):
                    mistIND = 1
                if ("HZ" in word):
                    hazeIND = 1
                if ("FG" in word):
                    fogIND = 1
        if currentCeiling == 99999:
            ceiling = default_ceiling
        else:
            ceiling = currentCeiling
            
        # iterate between the valid from time and the valid to time to obtain lines of predictors
        if validFromHr <= 23:
            validFromTM = datetime.datetime(validFromYr,validFromMon,validFromDay,validFromHr,validFromMin)
        else:
            validFromTM = datetime.datetime(validFromYr,validFromMon,validFromDay,validFromHr - 1,validFromMin)+datetime.timedelta(1/24.0)
        if validToHrK <= 23:
            validToTM = datetime.datetime(validToYrK,validToMonK,validToDayK,validToHrK,validToMinK)
        else:
            validToTM = datetime.datetime(validToYrK,validToMonK,validToDayK,validToHrK - 1,validToMinK)+datetime.timedelta(1/24.0)
        iterTM = validFromTM
        
        while iterTM < validToTM:
            # create a dictionary to show whether the time period within the TAF time range has been predicted
            # if so, append the data to the original list. Otherwise, start a new line
            timeCheck[(iterTM,typePt[i])] = [angle,speed,gust*gustSpeed,visibility,ceiling,plusIND,minusIND,snowIND,rainIND,thunderIND,icepalIND,hailIND,\
                mistIND,hazeIND,fogIND]
            # add 30 mins to iterTM
            iterTM += datetime.timedelta(1/48.0)
        default_ceiling = ceiling
    for iKey in timeCheck.keys():
        lag = (iKey[0] - issuedTime).seconds/3600.0 + (iKey[0] - issuedTime).days * 24
        tafPredictor[(iKey[0].year,iKey[0].month,iKey[0].day,iKey[0].hour,iKey[0].minute)] = [lag,iKey[1],iKey[0].month,iKey[0].hour]+timeCheck[iKey]
        
    
    # for each time period in the specified date range
    # change the time to Zulu time
    currentDate = startT.replace(tzinfo = local_tz).astimezone(pytz.utc) + datetime.timedelta(4/1440.0)
    currentDate = datetime. datetime(currentDate.year,currentDate.month,currentDate.day,currentDate.hour,currentDate.minute)
    endDate = endT.replace(tzinfo = local_tz).astimezone(pytz.utc) + datetime.timedelta(4/1440.0)
    endDate = datetime.datetime(endDate.year,endDate.month,endDate.day,endDate.hour,endDate.minute)
    preRow = []
    preCol = []
    preData = []
    tp = []
    row = 0
    while currentDate < endDate:
        if (currentDate.year,currentDate.month,currentDate.day,currentDate.hour,currentDate.minute) in tafPredictor.keys():
            entryList = tafPredictor[(currentDate.year,currentDate.month,currentDate.day,currentDate.hour,currentDate.minute)]
            Xwind = entryList[4]
            Xwind = windEnc.transform([txtEnc.transform(Xwind)]).toarray()
            for col in range(M1):
                if Xwind[0][col] != 0:
                    preData.append(Xwind[0][col])
                    preRow.append(row)
                    preCol.append(col)
            # month/hour/reportType
            Xcat = [entryList[2],entryList[3],entryList[1]]
            Xcat = catEnc.transform(Xcat).toarray()
            for col in range(M1,M1+M2):
                if Xcat[0][col - M1] != 0:
                    preData.append(Xcat[0][col - M1])
                    preRow.append(row)
                    preCol.append(col)
            Xdata = [entryList[0]]+entryList[5:]
            for col in range(M1+M2,M1+M2+len(Xdata)):
                if Xdata[col - M1 - M2] != 0:
                    preData.append(Xdata[col - M1 - M2])
                    preRow.append(row)
                    preCol.append(col)
            currentDate += datetime.timedelta(1/48.0)
            tp.append(row)
            row += 1
    Xsparse = coo_matrix((preData,(preRow,preCol)),shape=(row, M1+M2+M3))
    return Xsparse,tp

def detCapSeq(X,tp,clf,iniType):
    ypred = clf.predict(X)
    ypred = [iniType]+ypred
    fo = open("detCapSeq.csv","wb")
    csvWriter = csv.writer(fo,dialect = "excel")
    csvWriter.writerow(ypred)
    fo.close()
    
def scenMatGen(X,T,N,tp,clf,iniType):
    horizon = min(T,len(tp));
    Xstoch = X[1:horizon,:];
    if len(tp) > T:
        Xdet = X[T:,:]
    else:
        Xdet = []
    yprob = clf.predict_prob(Xstoch)
    if Xdet != []:
        ypred = clf.predict(Xdet)
    else:
        ypred = []
        
    # generate N scenarios
    elements = range(1,41)
    weatherMat = numpy.zeros([N,horizon])
    weatherMat[:,0] = iniType
    for t in range(1,horizon):
        probList = yprob[t-1,:]
        weatherMat[:,t] = numpy.random.choice(elements,N,probList)
    
    # generate the coonnection matrix
    currentPartition = {1:range(N)}
    connectionMat = numpy.zeros([N,horizon])
    for t in range(1,horizon):
        newPartition = {}
        for i in currentPartition.keys():
            iSet = {}
            for v in currentPartition[i]:
                connectionMat[v,t-1] = i
                if not(weatherMat[v,t] in iSet.keys()):
                    iSet[weatherMat[v,t]] = v
                    newPartition[v] = [v]
                else:
                    newPartition[iSet[weatherMat[v,t]]].append(v)
        currentPartition = newPartition
    for i in currentPartition.keys():
        for v in currentPartition[i]:
            connectionMat[v,horizon - 1] = i
    fo1 = open('weatherMat.csv',"wb")
    csvWriter = csv.writer(fo1,dialect = "excel")
    for n in len(weatherMat):
        printList = list(weatherMat[n,:])+ypred
        csvWriter.writerow(printList)
    fo1.close()
    fo2 = open('connectionoMat.csv',"wb")
    csvWriter = csv.writer(fo2,dialect = "excel")
    for n in len(connectionMat):
        printList = list(connectionMat[n,:])+[weatherMat[n,-1]]*len(ypred)
        csvWriter.writerow(printList)
    fo2.close()
    
        
        
    
def scenTreeGen(X, tp, clf, iniType):
    yprob = clf.predict_proba(X)
#    T = len(tp) - 1
    
    # total number of possible scenario
#    totalPoss = 1
    yl = numpy.array(range(len(yprob[0])))
    PossList = [[iniType]]
    ProbList = [[1]]
    for i in tp[1:]:
        yind = numpy.greater(yprob[i],0.05)
        PossList.append([j + 1 for j in list(yl[yind])])
        ProbList.append(list(yprob[i][yind]/(float(sum(yprob[i][yind])))))
#        totalPoss = totalPoss * sum(yind)
#    connMat = numpy.zeros([totalPoss,T+1])
#    scenMat = numpy.zeros([totalPoss,T+1])
#    breakL = 1
#    for t in range(T,-1,-1):
#        connMat[:,t] = numpy.repeat(range(1,totalPoss+1,breakL),breakL)
#        breakL = breakL*len(PossList[t])
#        scenMat[:,t] = numpy.array(list(numpy.repeat(PossList[t],breakL/len(PossList[t])))*(totalPoss/breakL))
#    return connMat.astype(int), scenMat.astype(int), PossList, ProbList
    return PossList,ProbList