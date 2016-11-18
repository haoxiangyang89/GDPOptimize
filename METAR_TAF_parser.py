# -*- coding: utf-8 -*-
"""
Created on Fri Jul 29 09:55:42 2016

@author: hyang
"""

# This is the METAR/TAF tool built to predict the weather based on METAR/TAF data
#       for ATL

# It can collect the METAR/TAF data from OGIMET and parse the data into csv format

# Based on the given data it can train the model to predict the likelihood of being
#       VFR, Marginal or IFR

# The address format:
# http://www.ogimet.com/display_metars2.php?lang=en&
#    lugar=KATL&tipo=ALL&ord=REV&nil=SI&fmt=html&ano=2016&mes=07&day=01&hora=00&
#    anof=2016&mesf=07&dayf=01&horaf=23&minf=59&send=send
from __future__ import division
import csv
import datetime
import time
import re
from selenium import webdriver
import os
import sqlite3
import pytz
#import pdb
#pdb.set_trace()

def btsCombining(path,airportName,dbName,actionType,fileList = []):
    # output title
    #titleOut = ["YEAR","MONTH","DAY_OF_MONTH","FL_DATE","UNIQUE_CARRIER","AIRLINE_ID","FL_NUM","ORIGIN_AIRPORT_ID","ORIGIN","ORIGIN_CITY_NAME",\
    #            "DEST_AIRPORT_ID","DEST","DEST_CITY_NAME","CRS_DEP_TIME","DEP_TIME","DEP_DELAY","CRS_ARR_TIME","ARR_TIME","ARR_DELAY",\
    #            "CANCELLED","CRS_ELAPSED_TIME","ACTUAL_ELAPSED_TIME","AIR_TIME"]
    if actionType == "w":
        fileList = os.listdir(path)
    elif actionType == "a":
        if fileList == []:
            raise ValueError('Need to input a list of file')
    else:
        raise ValueError('actionType has to be "a" or "w"')
    title = []
    btsDept = []
    btsArr = []
    
    for item in fileList:
        if item[-3:] == "csv":
            pathItem = os.path.join(path,item)
            fi = open(pathItem,"rb")
            csvReader = csv.reader(fi,dialect = "excel")
            counter = 0
            for entry in csvReader:
                try:
                    if counter == 0:
                        title = entry
                        counter += 1
                    else:
                        if entry[title.index("ORIGIN")] == airportName:
                            # add the entry to the database
                            # basic information of the flight
                            airline = entry[title.index("UNIQUE_CARRIER")]
                            flightNo = entry[title.index("FL_NUM")]
                            origin = entry[title.index("ORIGIN")]
                            dest = entry[title.index("DEST")]
                            cancelled = int(float(entry[title.index("CANCELLED")]))
                            diverted = int(float(entry[title.index("DIVERTED")]))
                            
                            # time information of the flight
                            planATime = int(entry[title.index("CRS_ARR_TIME")])
                            if planATime == 2400:
                                plannedArr = datetime.datetime(int(entry[title.index("YEAR")]),int(entry[title.index("MONTH")]),int(entry[title.index("DAY_OF_MONTH")]),\
                                                0,0) + datetime.timedelta(1)
                            else:
                                plannedArr = datetime.datetime(int(entry[title.index("YEAR")]),int(entry[title.index("MONTH")]),int(entry[title.index("DAY_OF_MONTH")]),\
                                                planATime//100,planATime%100)
                            try:
                                if entry[title.index("ARR_DELAY")]!='':
                                    ArrDelay = float(entry[title.index("ARR_DELAY")])
                                    actualArr = plannedArr + datetime.timedelta(ArrDelay/1440.0)
                                else:
                                    ArrDelay = None
                                    actATime = int(entry[title.index("ARR_TIME")])
                                    if actATime == 2400:
                                        actATime = 0
                                    if actATime//100 < planATime//100 - 10:
                                        actualArr = datetime.datetime(int(entry[title.index("YEAR")]),int(entry[title.index("MONTH")]),int(entry[title.index("DAY_OF_MONTH")]),\
                                                    actATime//100,actATime%100) + datetime.timedelta(1)
                                    else:
                                        actualArr = datetime.datetime(int(entry[title.index("YEAR")]),int(entry[title.index("MONTH")]),int(entry[title.index("DAY_OF_MONTH")]),\
                                                    actATime//100,actATime%100)
                            except:
                                actualArr = None                                
                                
                            planDTime = int(entry[title.index("CRS_DEP_TIME")])
                            if planDTime == 2400:
                                planDTime = 0
                            if planDTime//100 > planATime//100 + 10:
                                plannedDept = datetime.datetime(int(entry[title.index("YEAR")]),int(entry[title.index("MONTH")]),int(entry[title.index("DAY_OF_MONTH")]),\
                                                planDTime//100,planDTime%100) + datetime.timedelta(-1)
                            else:
                                plannedDept = datetime.datetime(int(entry[title.index("YEAR")]),int(entry[title.index("MONTH")]),int(entry[title.index("DAY_OF_MONTH")]),\
                                                planDTime//100,planDTime%100)
                            try:
                                if entry[title.index("DEP_DELAY")] != '':
                                    DeptDelay = float(entry[title.index("DEP_DELAY")])
                                    actualDept = plannedDept + datetime.timedelta(DeptDelay/1440.0)
                                else:
                                    DeptDelay = None
                                    actDTime = int(entry[title.index("DEP_TIME")])
                                    if actDTime == 2400:
                                        actDTime = 0
                                    if actDTime//100 > planATime//100 + 10:
                                        actualDept = datetime.datetime(int(entry[title.index("YEAR")]),int(entry[title.index("MONTH")]),int(entry[title.index("DAY_OF_MONTH")]),\
                                                        actDTime//100,actDTime%100) + datetime.timedelta(-1)
                                    else:
                                        actualDept = datetime.datetime(int(entry[title.index("YEAR")]),int(entry[title.index("MONTH")]),int(entry[title.index("DAY_OF_MONTH")]),\
                                                        actDTime//100,actDTime%100)
                                if actualDept.minute >= 30:
                                    binDept = datetime.datetime(actualDept.year,actualDept.month,actualDept.day,actualDept.hour,30)
                                else:
                                    binDept = datetime.datetime(actualDept.year,actualDept.month,actualDept.day,actualDept.hour,0)
                            except:
                                actDTime = None
                                actualDept = None
                                binDept = None
                                
                            try:
                                plannedEla = float(entry[title.index("CRS_ELAPSED_TIME")])
                            except:
                                plannedEla = None
                            try:
                                actualEla = float(entry[title.index("ACTUAL_ELAPSED_TIME")])
                            except:
                                actualEla = None
                            
                            btsDept.append((airline,flightNo,origin,dest,cancelled,diverted,plannedDept,plannedArr,\
                                    actualDept,actualArr,DeptDelay,ArrDelay,plannedEla,actualEla,binDept))
                                        
                        if entry[title.index("DEST")] == airportName:
                            # add the entry to the database
                            # basic information of the flight
                            airline = entry[title.index("UNIQUE_CARRIER")]
                            flightNo = entry[title.index("FL_NUM")]
                            origin = entry[title.index("ORIGIN")]
                            dest = entry[title.index("DEST")]
                            cancelled = int(float(entry[title.index("CANCELLED")]))
                            diverted = int(float(entry[title.index("DIVERTED")]))
                            
                                # add the entry to the database
                            # time information of the flight
                            planATime = int(entry[title.index("CRS_ARR_TIME")])
                            if planATime == 2400:
                                plannedArr = datetime.datetime(int(entry[title.index("YEAR")]),int(entry[title.index("MONTH")]),int(entry[title.index("DAY_OF_MONTH")]),\
                                                0,0) + datetime.timedelta(1)
                            else:
                                plannedArr = datetime.datetime(int(entry[title.index("YEAR")]),int(entry[title.index("MONTH")]),int(entry[title.index("DAY_OF_MONTH")]),\
                                                planATime//100,planATime%100)
                            try:
                                if entry[title.index("ARR_DELAY")]!='':
                                    ArrDelay = float(entry[title.index("ARR_DELAY")])
                                    actualArr = plannedArr + datetime.timedelta(ArrDelay/1440.0)
                                else:
                                    ArrDelay = None
                                    actATime = int(entry[title.index("ARR_TIME")])
                                    if actATime == 2400:
                                        actATime = 0
                                    if actATime//100 < planATime//100 - 10:
                                        actualArr = datetime.datetime(int(entry[title.index("YEAR")]),int(entry[title.index("MONTH")]),int(entry[title.index("DAY_OF_MONTH")]),\
                                                    actATime//100,actATime%100) + datetime.timedelta(1)
                                    else:
                                        actualArr = datetime.datetime(int(entry[title.index("YEAR")]),int(entry[title.index("MONTH")]),int(entry[title.index("DAY_OF_MONTH")]),\
                                                    actATime//100,actATime%100)
                                if actualArr.minute >= 30:
                                    binArr = datetime.datetime(actualArr.year,actualArr.month,actualArr.day,actualArr.hour,30)
                                else:
                                    binArr = datetime.datetime(actualArr.year,actualArr.month,actualArr.day,actualArr.hour,0)
                            except:
                                actualArr = None  
                                binArr = None
                                
                            planDTime = int(entry[title.index("CRS_DEP_TIME")])
                            if planDTime == 2400:
                                planDTime = 0
                            if planDTime//100 > planATime//100 + 10:
                                plannedDept = datetime.datetime(int(entry[title.index("YEAR")]),int(entry[title.index("MONTH")]),int(entry[title.index("DAY_OF_MONTH")]),\
                                                planDTime//100,planDTime%100) + datetime.timedelta(-1)
                            else:
                                plannedDept = datetime.datetime(int(entry[title.index("YEAR")]),int(entry[title.index("MONTH")]),int(entry[title.index("DAY_OF_MONTH")]),\
                                                planDTime//100,planDTime%100)
                            try:
                                if entry[title.index("DEP_DELAY")] != '':
                                    DeptDelay = float(entry[title.index("DEP_DELAY")])
                                    actualDept = plannedDept + datetime.timedelta(DeptDelay/1440.0)
                                else:
                                    DeptDelay = None
                                    actDTime = int(entry[title.index("DEP_TIME")])
                                    if actDTime == 2400:
                                        actDTime = 0
                                    if actDTime//100 > planATime//100 + 10:
                                        actualDept = datetime.datetime(int(entry[title.index("YEAR")]),int(entry[title.index("MONTH")]),int(entry[title.index("DAY_OF_MONTH")]),\
                                                        actDTime//100,actDTime%100) + datetime.timedelta(-1)
                                    else:
                                        actualDept = datetime.datetime(int(entry[title.index("YEAR")]),int(entry[title.index("MONTH")]),int(entry[title.index("DAY_OF_MONTH")]),\
                                                        actDTime//100,actDTime%100)
                            except:
                                actDTime = None
                                actualDept = None
                                
                            try:
                                plannedEla = float(entry[title.index("CRS_ELAPSED_TIME")])
                            except:
                                plannedEla = None
                            try:
                                actualEla = float(entry[title.index("ACTUAL_ELAPSED_TIME")])
                            except:
                                actualEla = None
                                
                            btsArr.append((airline,flightNo,origin,dest,cancelled,diverted,plannedDept,plannedArr,\
                                    actualDept,actualArr,DeptDelay,ArrDelay,plannedEla,actualEla,binArr))
                except:
                    print(entry)
            fi.close()
    
    # create a database and dump the data to the database
    conn = sqlite3.connect(dbName)
    c = conn.cursor()
    # create the table
    if actionType == "w":
        c.execute('''CREATE TABLE arrivals
                    (airline text, flight_No text, origin text, dest text, cancelled integer, diverted integer, plannedDeptT datetime, plannedArrT datetime, 
                    actualDeptT datetime, actualArrT datetime, deptDelay real, arrDelay real, plannedElapse real, actualElapse real, binArr datetime)''')
        c.execute('''CREATE TABLE departures
                    (airline text, flight_No text, origin text, dest text, cancelled integer, diverted integer, plannedDeptT datetime, plannedArrT datetime, 
                    actualDeptT datetime, actualArrT datetime, deptDelay real, arrDelay real, plannedElapse real, actualElapse real, binDept datetime)''')
    conn.commit()
    # close the connection
    c.executemany("INSERT INTO departures VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",btsDept)
    c.executemany("INSERT INTO arrivals VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",btsArr)
    conn.commit()
    conn.close()
    
#    foDept = open("BigDept_BTS_{}.csv".format(airportName),"wb")
#    csvWriter = csv.writer(foDept,dialect = "excel")
#    csvWriter.writerow(titleOut)
#    csvWriter.writerows(btsDeptData)
#    foDept.close()
#    foArr = open("BigArrData_BTS_{}.csv".format(airportName),"wb")
#    csvWriter = csv.writer(foArr,dialect = "excel")
#    csvWriter.writerow(titleOut)
#    csvWriter.writerows(btsArrData)
#    foArr.close()

#def btsConsolidate(deptFile,arrFile,metarFile):
#    fiMetar = open(metarFile,"rb")
#    csvReaderMetar = csv.reader(fiMetar,dialect = "excel")
#    fiDept = open(deptFile,"rb")
#    csvReaderDept = csv.reader(fiDept,dialect = "excel")
#    for item in csvReaderMetar:
#        a = 1

def dbDatetimeConvert(dbstring):
    dbList = dbstring.split(" ")
    dbDate = dbList[0]
    dbTime = dbList[1]
    dbDateList = dbDate.split("-")
    dbTimeList = dbTime.split(":")
    return datetime.datetime(int(dbDateList[0]),int(dbDateList[1]),int(dbDateList[2]),int(dbTimeList[0]),int(dbTimeList[1]),int(dbTimeList[2]))
        
def mtCombiningMetar(path,metarList,dbName,localTZ = 'US/Eastern'):
    # set up an empty dictionary for metar data
    metarDict = {}
    local_tz = pytz.timezone(localTZ)
    conn = sqlite3.connect(dbName)
    c = conn.cursor()
    # obtain the departure count and the arrival count!!!!!!!  
    c.execute("SELECT binDept,COUNT(*) FROM departures GROUP BY binDept")
    deptCountraw = c.fetchall()
    deptCountDict = {}
    for item in deptCountraw:
        if item[0] != None:
            deptCountDict[dbDatetimeConvert(item[0])] = item[1]
    c.execute("SELECT binArr,COUNT(*) FROM arrivals GROUP BY binArr")
    arrCountraw = c.fetchall()
    arrCountDict = {}
    for item in arrCountraw:
        if item[0] != None:
            arrCountDict[dbDatetimeConvert(item[0])] = item[1]
    
    # create a table for METAR/TAF data
    try:
        c.execute('''CREATE TABLE halfHourly
                    (ID integer, fromTime datetime, toTime datetime, noDept integer, noArr integer, windAngle text, windSpeed integer, gust integer, gustSpeed integer, visibility real, 
                    ceiling real, temp real, dewTemp real, pressure real, plus integer, minus integer, SN integer, PL integer, RA integer, TS integer, GR integer, 
                    BR integer, HZ integer, FG integer, VFR integer, Marginal integer, IFR integer, lowIFR integer)''')
    except:
        c.execute("DELETE FROM halfHourly")
    conn.commit()
    ID = 0
    # build the dictionary
    for item in metarList:
        fi = open(os.path.join(path,item),"rb")
        csvReader = csv.reader(fi,dialect = "excel")
        counter = 0
        for readItem in csvReader:
            if counter == 0:
                counter += 1
                title = readItem
            else:
                # record the start time and the end time of the entry
                if int(readItem[4]) <= 15:
                    startMin = 0
                elif int(readItem[4] <= 45):
                    startMin = 30
                UTCstartDate = datetime.datetime(int(readItem[0]),int(readItem[1]),int(readItem[2]),int(readItem[3]),startMin)
                startDate = UTCstartDate.replace(tzinfo = pytz.utc).astimezone(local_tz)
                startDate = datetime.datetime(startDate.year,startDate.month,startDate.day,startDate.hour,startDate.minute)
                UTCendDate = datetime.datetime(int(readItem[5]),int(readItem[6]),int(readItem[7]),int(readItem[8]),int(readItem[9]))
                endDate = UTCendDate.replace(tzinfo = pytz.utc).astimezone(local_tz)
                endDate = datetime.datetime(endDate.year,endDate.month,endDate.day,endDate.hour,endDate.minute)
                currentDate = startDate
                while currentDate < endDate:
                    if not(currentDate in metarDict.keys()):
                        # 10: wind angle, 11: wind speed, 12: gust indicator, 13: gust speed, 14: visibility, 15: ceiling
                        # 16: temperature, 17: dew temperature, 18: pressure, 19 and beyond: weather indicators
                        
                        # if snow appears
                        snowIND = int(readItem[title.index("SN")])
                        # if rain or drizzle appears
                        if int(readItem[title.index("RA")]) + int(readItem[title.index("DZ")]) >= 1:
                            rainIND = 1
                        else:
                            rainIND = 0
                        # if thunderstorm appears
                        thunderIND = int(readItem[title.index("TS")])
                        # if freezing or ice pallet appears
                        if int(readItem[title.index("FZ")]) + int(readItem[title.index("PL")]) >= 1:
                            icepalIND = 1
                        else:
                            icepalIND = 0
                        # if hail appears
                        if int(readItem[title.index("GR")]) + int(readItem[title.index("GS")]) >= 1:
                            hailIND = 1
                        else:
                            hailIND = 0
                        # if mist appears
                        mistIND = int(readItem[title.index("BR")])
                        hazeIND = int(readItem[title.index("HZ")])
                        fogIND = int(readItem[title.index("FG")])
                        # add the VFR/Marginal/IFR/low IFR information
                        ceiling = float(readItem[title.index("Ceiling")])
                        visibility = float(readItem[title.index("Visibility")])
                        if (ceiling >= 36) and (visibility >= 7):
                            VFR = 1
                            Marginal = 0
                            IFR = 0
                            lowIFR = 0
                        elif (ceiling >= 10) and (visibility >= 3):
                            VFR = 0
                            Marginal = 1
                            IFR = 0
                            lowIFR = 0
                        elif (ceiling >= 5) and (visibility >= 1):
                            VFR = 0
                            Marginal = 0
                            IFR = 1
                            lowIFR = 0
                        else:
                            VFR = 0
                            Marginal = 0
                            IFR = 0
                            lowIFR = 1
                            
                        metarDict[currentDate] = [readItem[10],float(readItem[11]),int(readItem[12]),float(readItem[13]),visibility,ceiling,\
                                float(readItem[16]),float(readItem[17]),float(readItem[18]),int(readItem[19]),int(readItem[20]),snowIND,icepalIND,rainIND,thunderIND,\
                                hailIND,mistIND,hazeIND,fogIND,VFR,Marginal,IFR,lowIFR]
                                
                        # create the hal-hourly table with the metar data and the count of flights
                        # extract the counter of flights during the half hour we are interested in
                        ID += 1
                        if currentDate in deptCountDict.keys():
                            countD = deptCountDict[currentDate]
                        else:
                            countD = 0
                        if currentDate in arrCountDict.keys():
                            countA = arrCountDict[currentDate]
                        else:
                            countA = 0
                        c.execute("INSERT INTO halfHourly VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",(ID,currentDate,currentDate+datetime.timedelta(1/48.0),\
                                countD,countA,readItem[10],float(readItem[11]),int(readItem[12]),float(readItem[13]),visibility,ceiling,\
                                float(readItem[16]),float(readItem[17]),float(readItem[18]),int(readItem[19]),int(readItem[20]),snowIND,icepalIND,rainIND,thunderIND,\
                                hailIND,mistIND,hazeIND,fogIND,VFR,Marginal,IFR,lowIFR))
                    currentDate = currentDate + datetime.timedelta(1/48.0)
        fi.close()
    conn.commit()
    conn.close()
    return metarDict
    
def readMetarDB(dbName):
    # connect ot the database
    conn = sqlite3.connect(dbName)
    c = conn.cursor()
    c.execute("SELECT fromTime, toTime, plus, minus, SN, PL, RA, TS, GR, BR, HZ, FG, VFR, Marginal, IFR, lowIFR FROM halfHourly")
    dump = c.fetchall()
    metarDict = {}
    for item in dump:
        fromTime = dbDatetimeConvert(item[1])
        metarDict[fromTime] = item[2:]
    return metarDict

def fortyTypes(metarEntry):
    metarEntryShort = metarEntry[2:6]+metarEntry[-4:]
    metarEntryDict = {(0,0,0,0,1,0,0,0):1, (0,0,0,0,0,1,0,0):2, (0,0,0,0,0,0,1,0):3, (0,0,0,0,0,0,0,1):4, \
                      (1,0,0,0,1,0,0,0):5, (1,0,0,0,0,1,0,0):6, (1,0,0,0,0,0,1,0):7, (1,0,0,0,0,0,0,1):8, \
                      (0,1,0,0,1,0,0,0):9, (0,1,0,0,0,1,0,0):10, (0,1,0,0,0,0,1,0):11, (0,1,0,0,0,0,0,1):12, \
                      (0,0,1,0,1,0,0,0):13, (0,0,1,0,0,1,0,0):14, (0,0,1,0,0,0,1,0):15, (0,0,1,0,0,0,0,1):16, \
                      (0,0,0,1,1,0,0,0):17, (0,0,0,1,0,1,0,0):18, (0,0,0,1,0,0,1,0):19, (0,0,0,1,0,0,0,1):20, \
                      (1,1,0,0,1,0,0,0):21, (1,1,0,0,0,1,0,0):22, (1,1,0,0,0,0,1,0):23, (1,1,0,0,0,0,0,1):24, \
                      (1,0,1,0,1,0,0,0):25, (1,0,1,0,0,1,0,0):26, (1,0,1,0,0,0,1,0):27, (1,0,1,0,0,0,0,1):28, \
                      (0,1,1,0,1,0,0,0):29, (0,1,1,0,0,1,0,0):30, (0,1,1,0,0,0,1,0):31, (0,1,1,0,0,0,0,1):32, \
                      (0,0,1,1,1,0,0,0):33, (0,0,1,1,0,1,0,0):34, (0,0,1,1,0,0,1,0):35, (0,0,1,1,0,0,0,1):36, \
                      (1,1,1,0,1,0,0,0):37, (1,1,1,0,0,1,0,0):38, (1,1,1,0,0,0,1,0):39, (1,1,1,0,0,0,0,1):40}
    if metarEntryShort in metarEntryDict.keys():
        wType = metarEntryDict[metarEntryShort]
    else:
        wType = 41
            
    return wType

def mtCombiningTaf(metarDict,path,tafList,dbName,localTZ = 'US/Eastern'):
    # read in the TAF predictor data
    conn2 = sqlite3.connect(dbName)
    c2 = conn2.cursor()
    local_tz = pytz.timezone(localTZ)
    c2.execute('''CREATE TABLE PreRes
                (ID integer, tafMonth integer, tafHour integer, tafDateTime datetime, Lag real, reportType integer, windAngle text, windSpeed integer, 
                gust integer, gustSpeed integer, visibility real, ceiling real, plus integer, minus integer, SN integer, PL integer, RA integer, 
                TS integer, GR integer, BR integer, HZ integer, FG integer, plus_METAR integer, minus_METAR integer, SN_METAR integer, PL_METAR integer, 
                RA_METAR integer, TS_METAR integer, GR_METAR integer, BR_METAR integer, HZ_METAR integer, FG_METAR integer, VFR_METAR integer, Marginal_METAR integer, 
                IFR_METAR integer, lowIFR_METAR integer, responseType integer)''')
#    c2.execute('''CREATE TABLE response
#                (ID integer, plus integer, minus integer, SN integer, PL integer, RA integer, TS integer, GR integer, BR integer, HZ integer, 
#                FG integer, VFR integer, Marginal integer, IFR integer, lowIFR integer)''')
    conn2.commit()
    ID = 0
    for item in tafList:
        addressItem = os.path.join(path,item)
        fi = open(addressItem,"rb")
        csvReader = csv.reader(fi,dialect = "excel")
        counter = 0
        predictorList = []
        #responseList = []
        for readItem in csvReader:
            if counter == 0:
                title = readItem
                counter += 1
            else:
                # read the time for TAF
                UTCtafDate = datetime.datetime(int(readItem[5]),int(readItem[6]),int(readItem[7]),int(readItem[8]),int(readItem[9]))
                tafDate = UTCtafDate.replace(tzinfo = pytz.utc).astimezone(local_tz)
                tafDate = datetime.datetime(tafDate.year,tafDate.month,tafDate.day,tafDate.hour,tafDate.minute)
                UTCissueDate = datetime.datetime(int(readItem[0]),int(readItem[1]),int(readItem[2]),int(readItem[3]),int(readItem[4]))
                issueDate = UTCissueDate.replace(tzinfo = pytz.utc).astimezone(local_tz)
                issueDate = datetime.datetime(issueDate.year,issueDate.month,issueDate.day,issueDate.hour,issueDate.minute)
                ID += 1
                
                lagTime = float(readItem[title.index("Lag Time")]) 
                reportType = int(readItem[title.index("Report Type")])
                
                # general TAF data
                windAngle = readItem[title.index("Wind Angle")]
                windSpeed = float(readItem[title.index("Wind Speed")])
                gust = int(readItem[title.index("Gust")])
                gustSpeed = float(readItem[title.index("GustSpeed")])
                visib = float(readItem[title.index("Visibility")])
                ceiling = float(readItem[title.index("Ceiling")])
                plusIND = int(readItem[title.index("+")])
                minusIND = int(readItem[title.index("-")])
                
                # if snow appears
                snowIND = int(readItem[title.index("SN")])
                # if rain or drizzle appears
                if int(readItem[title.index("RA")]) + int(readItem[title.index("DZ")]) >= 1:
                    rainIND = 1
                else:
                    rainIND = 0
                # if thunderstorm appears
                thunderIND = int(readItem[title.index("TS")])
                # if freezing or ice pallet appears
                if int(readItem[title.index("FZ")]) + int(readItem[title.index("PL")]) >= 1:
                    icepalIND = 1
                else:
                    icepalIND = 0
                # if hail appears
                if int(readItem[title.index("GR")]) + int(readItem[title.index("GS")]) >= 1:
                    hailIND = 1
                else:
                    hailIND = 0
                # if mist appears
                mistIND = int(readItem[title.index("BR")])
                hazeIND = int(readItem[title.index("HZ")])
                fogIND = int(readItem[title.index("FG")])
                if (tafDate in metarDict.keys()) and (issueDate in metarDict.keys()):
                    # 10: prediction lag, 11: report type
                    responseType = fortyTypes(metarDict[tafDate])
                    predictorList.append([ID, tafDate.month, tafDate.hour, tafDate, lagTime, reportType, windAngle,\
                        windSpeed, gust, gustSpeed, visib, ceiling, plusIND, minusIND, snowIND, icepalIND,\
                        rainIND, thunderIND, hailIND, mistIND, hazeIND, fogIND] + list(metarDict[issueDate]) + [responseType])
                    # add the entry to the database
                            
                    #responseList.append([ID]+list(metarDict[tafDate]))
        fi.close()
        c2.executemany("INSERT INTO PreRes VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",predictorList)
#        c2.executemany("INSERT INTO response VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",responseList)
    
    conn2.commit()
    conn2.close()
                    

def mtScraper(ICAO,startY,startM,startD,endY,endM,endD):
    # this is the scraper to scrape all the data, parse and store them in csv files
    # Input: the timespan we would like to retrieve the data for
    # Output: csv file that contains the specific range time

    # retrieve the data day by day
    startDate = datetime.date(startY,startM,startD)
    endDate = datetime.date(endY,endM,endD)
    currentDate = startDate
    weatherList = ["+","-","VC","MI","PR","BC","DR","BL","SH","TS","FZ","DZ","RA","SN",\
                    "SG","IC","PL","GR","GS","UP","BR","FG","FU","VA","DU","SA","HZ","PY",\
                    "PO","SQ","FC","SS"]
    
    foMETAR = open("MetarOut_{}_{}_{}.csv".format(ICAO,str(startY)+str(startM)+str(startD),str(endY)+str(endM)+str(endD)),"wb")
    foTAF = open("TafOut_{}_{}_{}.csv".format(ICAO,str(startY)+str(startM)+str(startD),str(endY)+str(endM)+str(endD)),"wb")
    foTAFPre = open("TafPreOut_{}_{}_{}.csv".format(ICAO,str(startY)+str(startM)+str(startD),str(endY)+str(endM)+str(endD)),"wb")
    csvWriter1 = csv.writer(foTAF,dialect = "excel")
    csvWriter2 = csv.writer(foMETAR,dialect = "excel")
    csvWriter3 = csv.writer(foTAFPre,dialect = "excel")
    browser = webdriver.Chrome("C:\\Users\\hyang\\Desktop\\chromedriver.exe")
    time.sleep(5)
    metarData = []
    tafData = []
    tafPredictor = []

    while currentDate <= endDate:
        if currentDate.month <= 11:
            newDate = datetime.date(currentDate.year,currentDate.month+1,1)
        else:
            newDate = datetime.date(currentDate.year+1, 1, 1)
        if newDate > endDate:
            newDate = endDate
        else:
            newDate = newDate + datetime.timedelta(-1)
        # open the web address
        mtAddress = "http://www.ogimet.com/display_metars2.php?lang=en&lugar={}&tipo=ALL&ord=REV&nil=NO&fmt=html&ano=\
                    {}&mes={}&day={}&hora={}&anof={}&mesf={}&dayf={}&horaf={}&minf={}&send=send".format(ICAO,currentDate.year,\
                    currentDate.month,currentDate.day,0,newDate.year,newDate.month,newDate.day,23,59)
        preList = []
        while len(preList) == 0:
            browser.get(mtAddress)
            preList = browser.find_elements_by_tag_name("pre")
            if len(preList) == 0:
                time.sleep(120)            
        
        # obtain all METAR/TAF data
        for item in preList:
            plainTXT = item.text.encode('utf-8')
            plainTXT = re.sub('\s+', ' ', plainTXT).strip()
            plainTXT = plainTXT[:-1]
            
            # obtain a list of elements in an entry of METAR or TAF
            itemList = plainTXT.split(" ")
            # Indicator of METAR
            if (itemList[0] == 'TAF')or(itemList[0] == ICAO):
                try:
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
                    issuedTime = datetime.datetime(currentDate.year,currentDate.month,dayIss,hourIss,minIss)
                    
                    # obtain the time the forecast is valid between
                    timestamp = datetime.datetime(currentDate.year,currentDate.month,dayIss,hourIss) + datetime.timedelta(1/24.0)
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
                        elif (itemList[i] == "PROB30"):
                            eventPt.append(i)
                            typePt.append(3)
                        elif (itemList[i] == "PROB40"):
                            eventPt.append(i)
                            typePt.append(4)
                    
                    eventPt.append(len(itemList))
                    typePt.append(5)
                            
                    # examine each segment
                    fmCounter = 0
                    probNu = 1
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
                                for iKey in weatherList:
                                    if iKey in word:
                                        weatherDict[iKey] = 1
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
                            timeCheck[(iterTM,typePt[i])] = [angle,speed,gust,gustSpeed,visibility,ceiling]
                            for iKey in weatherList:
                                timeCheck[(iterTM,typePt[i])].append(weatherDict[iKey])
                            # add 30 mins to iterTM
                            iterTM += datetime.timedelta(1/48.0)
                        oneEntry = [currentDate.year,currentDate.month,dayIss,hourIss,minIss,probNu,validFromYr,validFromMon,validFromDay,validFromHr,validFromMin,\
                        validToYrK,validToMonK,validToDayK,validToHrK,validToMinK,angle,speed,gust,gustSpeed,\
                        visibility,ceiling]
                        for iKey in weatherList:
                            oneEntry.append(weatherDict[iKey])
                        tafData.append(oneEntry)
                        default_ceiling = ceiling
                    for iKey in timeCheck.keys():
                        lag = (iKey[0] - issuedTime).seconds/3600 + (iKey[0] - issuedTime).days * 24
                        if issuedTime.minute >= 30:
                            minIssue = 30
                        else:
                            minIssue = 0
                        tafPredictor.append([issuedTime.year,issuedTime.month,issuedTime.day,issuedTime.hour,minIssue,\
                                            iKey[0].year,iKey[0].month,iKey[0].day,iKey[0].hour,iKey[0].minute,lag,iKey[1]]+timeCheck[iKey])
                except:
                    print(itemList)
            else:
                # it is a METAR or SPECI entry
                weatherDict = {}
                for iKey in weatherList:
                    weatherDict[iKey] = 0
                if itemList[0] == 'SPECI':
                    typeSPECI = 1
                else:
                    typeSPECI = 0
                # append the year/month/date of the data
                startEnt = 2
                # the METAR entry end before RMK (remark)
                try:
                    endEnt = itemList.index("RMK")
                except:
                    endEnt = len(itemList) - 1
                    print(itemList)
                ceiling = 120
                while startEnt < endEnt:
                    tempEnt = itemList[startEnt]
                    try:
                        # check if the current index shows the time of report
                        if re.findall("[0-9]+Z",tempEnt) != []:
                            dayEnt = int(tempEnt[:2])
                            hourEnt = int(tempEnt[-5:-3])            
                            minEnt = int(tempEnt[-3:-1])
                            timestamp = datetime.datetime(currentDate.year,currentDate.month,dayEnt,hourEnt,minEnt)
                            validto = datetime.datetime(currentDate.year,currentDate.month,dayEnt,hourEnt)+datetime.timedelta(1/24.0)
                            if (1-typeSPECI)or(minEnt >= 45):
                                # valid from
                                validFromYr = validto.year
                                validFromMon = validto.month
                                validFromDay = validto.day
                                validFromHr = validto.hour
                                validFromMin = validto.minute
                                validtoNew = validto + datetime.timedelta(1/24.0)
                                # valid to
                                validToYr = validtoNew.year
                                validToMon = validtoNew.month
                                validToDay = validtoNew.day
                                validToHr = validtoNew.hour
                                validToMin = validtoNew.minute
                            else:
                                # valid from
                                validFromYr = timestamp.year
                                validFromMon = timestamp.month
                                validFromDay = timestamp.day
                                validFromHr = timestamp.hour
                                validFromMin = timestamp.minute
                                # valid to
                                validToYr = validto.year
                                validToMon = validto.month
                                validToDay = validto.day
                                validToHr = validto.hour
                                validToMin = validto.minute
                        
                        # check if the current index shows the wind speed
                        if tempEnt[-2:] == "KT":
                            angle = tempEnt[:3]
                            speed = int(tempEnt[-4:-2])
                            if tempEnt.find("G") == -1:
                                gust = 0
                                gustSpeed = -1
                            else:
                                gust = 1
                                gustSpeed = int(tempEnt[tempEnt.find("G")-2:tempEnt.find("G")])
                                
                        # check if the current index shows the visibility
                        if tempEnt[-2:] == "SM":
                            if tempEnt[0] == "P":
                                visibility = 10
                            else:
                                visibility = eval(tempEnt[:-2])
                        
                        # check if the current index shows the cloud information
                        if ("BKN" in tempEnt) or ("OVC" in tempEnt) or ("VV" in tempEnt):
                            ceiling = min(ceiling,int(re.findall("[0-9]+",tempEnt)[0]))
                        else:
                            # check if the current index shows the certain type of weather
                            for iKey in weatherList:
                                if iKey in tempEnt:
                                    weatherDict[iKey] = 1
                            
                        # check if the current index shows the temperature
                        tempString = re.findall("M*[0-9]+/M*[0-9]+",tempEnt)
                        if  tempString!= []:
                            if tempString[0] == tempEnt:
                                tempList = tempEnt.split("/")
                                if "M" in tempList[0]:
                                    currentTemp = -int(tempList[0][1:])
                                else:
                                    currentTemp = int(tempList[0])
                                if "M" in tempList[1]:
                                    dewTemp = -int(tempList[1][1:])
                                else:
                                    dewTemp = int(tempList[1])
                                
                        # check if the current index shows the pressure
                        if re.findall("A[0-9]+",tempEnt) != []:
                            pressure = int(tempEnt[1:])/100
                    except:
                        print(tempEnt)
                    
                    # update the index
                    startEnt += 1
                
                # compile one entry
                oneEntry = [validFromYr,validFromMon,validFromDay,validFromHr,validFromMin,\
                    validToYr,validToMon,validToDay,validToHr,validToMin,angle,speed,gust,gustSpeed,\
                    visibility,ceiling,currentTemp,dewTemp,pressure]
                for iKey in weatherList:
                    oneEntry.append(weatherDict[iKey])
                metarData.append(oneEntry)
        
        currentDate = newDate + datetime.timedelta(1)
    title1 = ["Issued Year","Issued Month","Issued Day","Issued Hour","Issued Minute","Probability","From Year",\
            "From Month","From Day","From Hour","From Minute",\
            "To Year","To Month","To Day","To Hour","To Minute","Wind Angle","Wind Speed","Gust","GustSpeed",\
            "Visibility","Ceiling"]
    titlePre = ["Issuance Year","Issuance Month","Issuance Day","Issuance Hour","Issuance Minute",\
            "Predicted Year","Predicted Month","Predicted Day","Predicted Hour","Predicted Minute",\
            "Lag Time","Report Type","Wind Angle","Wind Speed","Gust","GustSpeed","Visibility","Ceiling"]
    title2 = ["From Year","From Month","From Day","From Hour","From Minute",\
            "To Year","To Month","To Day","To Hour","To Minute","Wind Angle","Wind Speed","Gust","GustSpeed",\
            "Visibility","Ceiling","Temperature","Dew Temperature","Pressure"]
    for item in weatherList:
        title1.append(item)
        title2.append(item)
        titlePre.append(item)
    csvWriter1.writerow(title1)
    csvWriter2.writerow(title2)
    csvWriter3.writerow(titlePre)
    csvWriter1.writerows(tafData)
    csvWriter2.writerows(metarData)
    csvWriter3.writerows(tafPredictor)
    foTAF.close()
    foMETAR.close()
    foTAFPre.close()
    del csvWriter1
    del csvWriter2
    del csvWriter3