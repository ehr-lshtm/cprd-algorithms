*********************
*********************
****Created on 28 September 2020 by Angel Wong
****Same logic as GOLD algorithm - only add the information of quantity identified from Observation files
****For `alcoholstatusvar'==3; their alcstatus is uncertain - depending on their value
****If alclevel==0, only when alcstatus==3 (based on value) or alcstatus==0 we can classify them as non-drinker
**********************
**********************

/*alcstatuslab:
           0 non
           1 curr
           2 ex

alclevellab:
           1 L
           2 M
           3 H
*/

*pr_getalcoholstatus
*Adds alcohol status to a file containing patid and an index date
*A "level" variable is required in the codelist file: it should be coded as 1=low, 2=med, 3=high, .=missing values

cap prog drop pr_getalcoholstatus
program define pr_getalcoholstatus

syntax, obsfile(string) icdfile(string) numunitfile(string) therapyfile(string) alcoholstatusvar(string) alcohollevelvar(string) unit_time(string) index(string)

noi di
noi di in yellow _dup(5) "*"
noi di in yellow "Assign alcohol status/level (from either clinical codes, or values from observation file),"
noi di in yellow "based on nearest status pre index date:"
noi di in yellow _dup(5) "*"

qui{


****************************************************************************************
*GET ALCOHOL STATUS FROM ICD CODES AND PRESCRIPTIONS FOR ANTABUSE
****************************************************************************************

preserve
merge 1:m patid using `icdfile', keep(match) nogen
rename epistart eventdate
keep patid eventdate `index' `alcoholstatusvar' `alcohollevelvar'
tempfile icddata
save `icddata'
restore

preserve
merge 1:m patid using `therapyfile', keep(match) nogen
rename issuedate eventdate
keep patid eventdate `index' `alcoholstatusvar' `alcohollevelvar'
tempfile therapydata
save `therapydata'
restore


****************************************************************************************
*GET ALCOHOL STATUS FROM CODES, AND SUPPLEMENT VALUES FROM OBS FILES
****************************************************************************************
merge 1:m patid using `obsfile', keep(match master) ///
keepusing(obsdate numunitid medcodeid value `alcoholstatusvar' `alcohollevelvar') nogen

rename obsdate eventdate

merge m:1 numunitid using `numunitfile', keepusing(`unit_time') keep(master match) nogen 

* Update alcohol level using unit file
rename `alcohollevelvar' `alcohollevelvar'_code

merge m:1 numunitid using `numunitfile', keepusing(`alcohollevelvar') ///
keep(master match) nogen 

rename `alcohollevelvar' `alcohollevelvar'_unit

* Take the highest amount of level considering both medcodeid and unit files
gen `alcohollevelvar' = max(`alcohollevelvar'_code, `alcohollevelvar'_unit)

drop `alcohollevelvar'_code `alcohollevelvar'_unit

* Only use the value recorded when unit of time is available (~1% records with value recorded but no unit of time)
destring value, replace

gen unitperwk=value       if `unit_time'==1
replace unitperwk=value   if medcodeid=="556651000000116" //unit per week
replace unitperwk=value*7 if `unit_time'==3 //per day

replace `alcohollevelvar' = . if `alcohollevelvar'==. & unitperwk==. 
replace `alcohollevelvar' = . if `alcohollevelvar'==. & unitperwk!=. & unitperwk==0 
replace `alcohollevelvar' = 1 if `alcohollevelvar'==. & unitperwk!=. & unitperwk>0 & unitperwk<=14 
replace `alcohollevelvar' = 2 if `alcohollevelvar'==. & unitperwk!=. & unitperwk>=15 & unitperwk<=42
replace `alcohollevelvar' = 3 if `alcohollevelvar'==. & unitperwk!=. & unitperwk>=43 & unitperwk<10000

* Edit alcohol status depending on alcohol level value from observation file
replace `alcoholstatusvar' = 1 if unitperwk!=. & unitperwk>0 & `alcoholstatusvar'==3
replace `alcoholstatusvar' = 1 if (`unit_time' == 2 | `unit_time' == 4) & `alcoholstatusvar'==3
replace `alcoholstatusvar' = 0 if unitperwk!=. & unitperwk==0 & `alcoholstatusvar'==3

* Remove records with value recorded but no unit of time
drop if unit_time==. & `alcoholstatusvar'==3

* Drop unnecessary variables
drop unit_time unitperwk

append using `icddata'
append using `therapydata'

*********************************************************
*ASSIGN STATUS BASED ON INDEX DATE, USING ALGORITHM BELOW
*********************************************************
*Algorithm:
*Take the nearest status of -1y to +1month from index (best)
*then nearest up to 1y after (second best)*
*then any before (third best)
*then any after (least best)

gen _distance = eventdate-`index'
gen _priority = 1 if _distance>=-365 & _distance<=30
replace _priority = 2 if _distance>30 & _distance<=365
replace _priority = 3 if _distance<-365
replace _priority = 4 if _distance>365 & _distance<.
gen _absdistance = abs(_distance)

recode `alcoholstatusvar' 0=9                         //new
gsort patid _priority _absdistance `alcoholstatusvar' -`alcohollevelvar'  //new

*Patients nearest status is non-drinker, but have history of drinking, recode to ex-drinker.
recode `alcoholstatusvar' 9=0   //new
by patid: egen ever_alc=sum(`alcoholstatusvar') 
by patid: replace `alcoholstatusvar' = 2 if ever_alc>0 & `alcoholstatusvar'==0

gsort patid _priority _absdistance `alcoholstatusvar' -`alcohollevelvar'  //new 
//no need to recode non-drinker as 9 for sorting because already coded as 2 in the above step if appear to have ex-/current-drinker code other than non-drinker

* if `alcohollevelvar' was missing at the first entry; use the highest consumption one within the same _priority to replace missing //new
bysort patid _priority: egen max_`alcohollevelvar' = max(`alcohollevelvar')    //new
replace `alcohollevelvar' = max_`alcohollevelvar' if `alcohollevelvar' == . //new

sort patid
by patid: keep if _n==1

//new: recode alcohol level if alcohol level==0 & ex-/non drinker do not have `alcohollevelvar'
replace `alcohollevelvar'=. if `alcohollevelvar'==0
replace `alcohollevelvar'=. if `alcoholstatusvar'==0
replace `alcohollevelvar'=. if `alcoholstatusvar'==2

//new: recode alcohol status if alcohol level >= 1 and alcohol status depends on level (i.e. alcstatus==3)
replace `alcoholstatusvar' = 1 if `alcoholstatusvar'== 3 & `alcohollevelvar' == 1
replace `alcoholstatusvar' = 1 if `alcoholstatusvar'== 3 & `alcohollevelvar' == 2
replace `alcoholstatusvar' = 1 if `alcoholstatusvar'== 3 & `alcohollevelvar' == 3

keep patid `index' eventdate `alcoholstatusvar' `alcohollevelvar'

}/*end of quietly*/

end

