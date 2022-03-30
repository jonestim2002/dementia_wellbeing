* Change directory to the relevant BDWS folder
cd "\\EVM-DC1-HES-P0.services.bris.ac.uk\Projects\Ben-Shlomo\2014_APC_BDWS\Data"
set more off

local do_lookups no
local process_raw_data no
local process_demographics no
local combine_data_demographics no
local demographics_by_ccg_2014 no
local rates_in_2014 no
local combine_demographics_2014 no
local monthly_data no
local monthly_acsc_data no
local analyse_acsc yes


***

if "`do_lookups'" == "yes" {
	* Prepare a lookup from LSOA2011 to CCG2017
	import delimited Lookups\LSOA2011_CCG2017_LAD2017.csv, clear
	rename ïlsoa11cd lsoa11
	drop ccg17cdh lad17cd lad17nm fid
	save "Lookups\lsoa11_ccg17.dta", replace

	***

	* Prepare an ethnicity lookup
	import excel "Lookups\Ethnic_Groups.xlsx", sheet("Sheet1") firstrow clear
	save "Lookups\ethnic_groups.dta", replace

	***

	* Prepare the QOF data with list size and dementia register
	import excel "Lookups\QOF\qof-1314-dementia-tj.xlsx", sheet("DEM") firstrow clear
	save "Lookups\QOF\qof_dementia_13_14.dta", replace
	
	import excel "Lookups\QOF\qof-1415-dementia-tj.xlsx", sheet("DEM") firstrow clear
	save "Lookups\QOF\qof_dementia_14_15.dta", replace

	import excel "Lookups\QOF\qof-1516-dementia-tj.xlsx", sheet("DEM") firstrow clear
	save "Lookups\QOF\qof_dementia_15_16.dta", replace

	import excel "Lookups\QOF\qof-1617-dementia-tj.xlsx", sheet("DEM") firstrow clear
	save "Lookups\QOF\qof_dementia_16_17.dta", replace
	
	import excel "Lookups\QOF\qof-1718-dementia-tj.xlsx", sheet("DEM") firstrow clear
	save "Lookups\QOF\qof_dementia_17_18.dta", replace	
	
	import excel "Lookups\QOF\qof-1819-dementia-tj.xlsx", sheet("DEM") firstrow clear
	save "Lookups\QOF\qof_dementia_18_19.dta", replace		

	use "Lookups\QOF\qof_dementia_13_14.dta", clear
	append using "Lookups\QOF\qof_dementia_14_15.dta" "Lookups\QOF\qof_dementia_15_16.dta" "Lookups\QOF\qof_dementia_16_17.dta" "Lookups\QOF\qof_dementia_17_18.dta" "Lookups\QOF\qof_dementia_18_19.dta"

	* Only keep practices for which we have denominators for all 6 years
	bysort gpprac: gen pracyears = _N
	tab pracyears
	/*
  pracyears |      Freq.     Percent        Cum.
------------+-----------------------------------
          1 |         26        0.06        0.06
          2 |        392        0.88        0.94
          3 |        621        1.40        2.33
          4 |      1,200        2.70        5.03
          5 |      2,100        4.72        9.75
          6 |     40,176       90.25      100.00
------------+-----------------------------------
      Total |     44,515      100.00
	*/
	
	drop if pracyears < 6
	drop pracyears

	* Check for changes in CCG in different years
	bysort gpprac QOF_CCG_Name: gen gpccgnum = _N
	tab gpccgnum
	/*
   gpccgnum |      Freq.     Percent        Cum.
------------+-----------------------------------
          1 |      7,178       17.87       17.87
          2 |        374        0.93       18.80
          3 |        519        1.29       20.09
          4 |      1,820        4.53       24.62
          5 |     30,285       75.38      100.00
------------+-----------------------------------
      Total |     40,176      100.00
	*/

	tab QOF_CCG_Name if gpccgnum < 6
	drop gpccgnum

	* In this case I'll use (2016/17) CCG membership for all 3 years - not 2017/18 because I want to keep Bristol CCG separate from NS and SG and they combined in 2017/18
	preserve
		keep if Fin_Year == 2016
		keep gpprac QOF_CCG_Code QOF_CCG_Name
		order gpprac QOF_CCG_Code QOF_CCG_Name
		sort gpprac QOF_CCG_Code QOF_CCG_Name
		tempfile gp_ccgs
		save `gp_ccgs', replace
	restore

	drop QOF_CCG_Code QOF_CCG_Name
	merge m:1 gpprac using `gp_ccgs', keep(1 3) nogen

	bysort gpprac QOF_CCG_Name: gen gpccgnum = _N
	tab gpccgnum
	/*
   gpccgnum |      Freq.     Percent        Cum.
------------+-----------------------------------
          6 |     40,176      100.00      100.00
------------+-----------------------------------
      Total |     40,176      100.00
	*/
	drop gpccgnum

	gen similar_ccg = 0
	replace similar_ccg = 1 if QOF_CCG_Name == "NHS BRIGHTON AND HOVE CCG" | QOF_CCG_Name == "NHS SHEFFIELD CCG" | QOF_CCG_Name == "NHS NORWICH CCG" | QOF_CCG_Name == "NHS PORTSMOUTH CCG" | QOF_CCG_Name == "NHS SOUTHAMPTON CCG" | ///
	QOF_CCG_Name == "NHS LIVERPOOL CCG" | QOF_CCG_Name == "NHS SUNDERLAND CCG" | QOF_CCG_Name == "NHS HULL CCG" | QOF_CCG_Name == "NHS SALFORD CCG" | QOF_CCG_Name == "NHS COVENTRY AND RUGBY CCG"

	save "Lookups\QOF\qof_dementia_allyears.dta", replace

	* Do CCG populations for each year
	collapse (sum) pop=QOF_List_Size dementia=QOF_Dementia, by(QOF_CCG_Name Fin_Year similar_ccg)
	save "Lookups\QOF\ccg_dementia_allyears.dta", replace
}

***
if "`process_raw_data'" == "yes" {
	* Import the raw data and cut down to just the fields needed
	import delimited Raw_Data\bdws_v3.csv, clear
	
	* Number of comorbidities (simple count of other listed diagnoses)
	egen num_comorb = rownonmiss(diag_*), strok
	
	* Check the dementia diagnosis
	gen F00_Alz = 0
	replace F00_Alz = 1 if strpos(diag_01, "F00") | strpos(diag_02, "F00") | strpos(diag_03, "F00") | strpos(diag_04, "F00") | strpos(diag_05, "F00") | strpos(diag_06, "F00") | strpos(diag_07, "F00") | strpos(diag_08, "F00") | strpos(diag_09, "F00") | strpos(diag_10, "F00") | strpos(diag_11, "F00") | strpos(diag_12, "F00") | strpos(diag_13, "F00") | strpos(diag_14, "F00") | strpos(diag_15, "F00") | strpos(diag_16, "F00") | strpos(diag_17, "F00") | strpos(diag_18, "F00") | strpos(diag_19, "F00") | strpos(diag_20, "F00")	
	gen F01_Vasc = 0
	replace F01_Vasc = 1 if strpos(diag_01, "F01") | strpos(diag_02, "F01") | strpos(diag_03, "F01") | strpos(diag_04, "F01") | strpos(diag_05, "F01") | strpos(diag_06, "F01") | strpos(diag_07, "F01") | strpos(diag_08, "F01") | strpos(diag_09, "F01") | strpos(diag_10, "F01") | strpos(diag_11, "F01") | strpos(diag_12, "F01") | strpos(diag_13, "F01") | strpos(diag_14, "F01") | strpos(diag_15, "F01") | strpos(diag_16, "F01") | strpos(diag_17, "F01") | strpos(diag_18, "F01") | strpos(diag_19, "F01") | strpos(diag_20, "F01")	
	gen F02_Other = 0
	replace F02_Other = 1 if strpos(diag_01, "F02") | strpos(diag_02, "F02") | strpos(diag_03, "F02") | strpos(diag_04, "F02") | strpos(diag_05, "F02") | strpos(diag_06, "F02") | strpos(diag_07, "F02") | strpos(diag_08, "F02") | strpos(diag_09, "F02") | strpos(diag_10, "F02") | strpos(diag_11, "F02") | strpos(diag_12, "F02") | strpos(diag_13, "F02") | strpos(diag_14, "F02") | strpos(diag_15, "F02") | strpos(diag_16, "F02") | strpos(diag_17, "F02") | strpos(diag_18, "F02") | strpos(diag_19, "F02") | strpos(diag_20, "F02")	
	gen F03_Unspec = 0
	replace F03_Unspec = 1 if strpos(diag_01, "F03") | strpos(diag_02, "F03") | strpos(diag_03, "F03") | strpos(diag_04, "F03") | strpos(diag_05, "F03") | strpos(diag_06, "F03") | strpos(diag_07, "F03") | strpos(diag_08, "F03") | strpos(diag_09, "F03") | strpos(diag_10, "F03") | strpos(diag_11, "F03") | strpos(diag_12, "F03") | strpos(diag_13, "F03") | strpos(diag_14, "F03") | strpos(diag_15, "F03") | strpos(diag_16, "F03") | strpos(diag_17, "F03") | strpos(diag_18, "F03") | strpos(diag_19, "F03") | strpos(diag_20, "F03")	
	gen F051_Del = 0
	replace F051_Del = 1 if strpos(diag_01, "F051") | strpos(diag_02, "F051") | strpos(diag_03, "F051") | strpos(diag_04, "F051") | strpos(diag_05, "F051") | strpos(diag_06, "F051") | strpos(diag_07, "F051") | strpos(diag_08, "F051") | strpos(diag_09, "F051") | strpos(diag_10, "F051") | strpos(diag_11, "F051") | strpos(diag_12, "F051") | strpos(diag_13, "F051") | strpos(diag_14, "F051") | strpos(diag_15, "F051") | strpos(diag_16, "F051") | strpos(diag_17, "F051") | strpos(diag_18, "F051") | strpos(diag_19, "F051") | strpos(diag_20, "F051")
	gen F059_Del_Unspec = 0
	replace F059_Del_Unspec = 1 if strpos(diag_01, "F059") | strpos(diag_02, "F059") | strpos(diag_03, "F059") | strpos(diag_04, "F059") | strpos(diag_05, "F059") | strpos(diag_06, "F059") | strpos(diag_07, "F059") | strpos(diag_08, "F059") | strpos(diag_09, "F059") | strpos(diag_10, "F059") | strpos(diag_11, "F059") | strpos(diag_12, "F059") | strpos(diag_13, "F059") | strpos(diag_14, "F059") | strpos(diag_15, "F059") | strpos(diag_16, "F059") | strpos(diag_17, "F059") | strpos(diag_18, "F059") | strpos(diag_19, "F059") | strpos(diag_20, "F059")
	gen G30_Alz = 0
	replace G30_Alz = 1 if strpos(diag_01, "G30") | strpos(diag_02, "G30") | strpos(diag_03, "G30") | strpos(diag_04, "G30") | strpos(diag_05, "G30") | strpos(diag_06, "G30") | strpos(diag_07, "G30") | strpos(diag_08, "G30") | strpos(diag_09, "G30") | strpos(diag_10, "G30") | strpos(diag_11, "G30") | strpos(diag_12, "G30") | strpos(diag_13, "G30") | strpos(diag_14, "G30") | strpos(diag_15, "G30") | strpos(diag_16, "G30") | strpos(diag_17, "G30") | strpos(diag_18, "G30") | strpos(diag_19, "G30") | strpos(diag_20, "G30")
	gen G31_Other = 0
	replace G31_Other = 1 if strpos(diag_01, "G31") | strpos(diag_02, "G31") | strpos(diag_03, "G31") | strpos(diag_04, "G31") | strpos(diag_05, "G31") | strpos(diag_06, "G31") | strpos(diag_07, "G31") | strpos(diag_08, "G31") | strpos(diag_09, "G31") | strpos(diag_10, "G31") | strpos(diag_11, "G31") | strpos(diag_12, "G31") | strpos(diag_13, "G31") | strpos(diag_14, "G31") | strpos(diag_15, "G31") | strpos(diag_16, "G31") | strpos(diag_17, "G31") | strpos(diag_18, "G31") | strpos(diag_19, "G31") | strpos(diag_20, "G31")
	egen num_dem_diag = rowtotal(F00_Alz F01_Vasc F02_Other F03_Unspec F051_Del F059_Del_Unspec G30_Alz G31_Other)
	
	* According to latest email from Shaun Popel on 4th April 2019, we should exclude entries that only have a F059 (Delerium Unspecified) diagnosis
	drop if num_dem_diag == 1 & F059_Del_Unspec == 1  // (733,004 observations deleted)
	
	* Latest decision from Yoav (December 2021) is to drop F02 - "Dementia in other diseases classified elsewhere (e.g. Huntington's, Parkinson's)" and to drop G31 - "Other degenerative diseases of nervous system, not elsewhere classified"
	keep if F00_Alz | F01_Vasc | F03_Unspec | F051_Del | G30_Alz
	
	**************************************************
	
	*** ACSC Conditions *** Based on the NHS Ambulatory Emergency Care Directory V6 Feb 2018
	gen acsc1st = .

	/*deep vein thrombosis*/
	replace acsc1st=1 if strpos(diag_01,"I801") | strpos(diag_01, "I802") | strpos(diag_01,"I822") | ///
			strpos(diag_01, "I803") | strpos(diag_01, "M796") | strpos(diag_01, "M798") 

	/*Pulmonary Embolism*/
	replace acsc1st=2 if strpos(diag_01,"I260") | strpos(diag_01,"I269") | strpos(diag_01,"R071") | strpos(diag_01,"R091")			

	/*Pneumothorax*/
	replace acsc1st=3 if strpos(diag_01,"J930") | strpos(diag_01,"J931") | strpos(diag_01,"J938") | strpos(diag_01,"J939") 
			
	/*Pleural effusions*/
	replace acsc1st=4 if strpos(diag_01,"C782") | strpos(diag_01,"J111") | strpos(diag_01,"J90") | strpos(diag_01,"J91") | ///
			strpos(diag_01,"J940") | strpos(diag_01,"J948")
			
	/*Asthma*/
	replace acsc1st=5 if strpos(diag_01,"J450") | strpos(diag_01,"J451") | strpos(diag_01,"J458") | strpos(diag_01,"J459") 

	/*COPD*/
	replace acsc1st=6 if strpos(diag_01,"J210") | strpos(diag_01,"J211") | strpos(diag_01,"J218") | ///
			strpos(diag_01,"J219") | strpos(diag_01,"J40") | strpos(diag_01,"J410") | strpos(diag_01,"J42") | ///
			strpos(diag_01,"J431") | strpos(diag_01,"J432") | strpos(diag_01,"J438") | strpos(diag_01,"J439") | ///
			strpos(diag_01,"J440") | strpos(diag_01,"J441") | strpos(diag_01,"J448") | strpos(diag_01,"J449") 

	/*Community Acquired Pneumonia*/
	replace acsc1st=7 if strpos(diag_01,"J100") | strpos(diag_01,"J110") | strpos(diag_01,"J120") | strpos(diag_01,"J121") | ///
			strpos(diag_01,"J122") | strpos(diag_01,"J123") | strpos(diag_01,"J128") | strpos(diag_01,"J129") | ///
			strpos(diag_01,"J13") | strpos(diag_01,"J14") | strpos(diag_01,"J153") | strpos(diag_01,"J154") | ///
			strpos(diag_01,"J155") | strpos(diag_01,"J156") | strpos(diag_01,"J157") | strpos(diag_01,"J158") | ///
			strpos(diag_01,"J159") | strpos(diag_01,"J160") | strpos(diag_01,"J168") | strpos(diag_01,"J170") | ///
			strpos(diag_01,"J171") | strpos(diag_01,"J178") | strpos(diag_01,"J180") | strpos(diag_01,"J181") | ///
			strpos(diag_01,"J188") | strpos(diag_01,"J189") 

	/*LRTI without COPD*/
	replace acsc1st=8 if strpos(diag_01,"J200") | strpos(diag_01,"J201") | strpos(diag_01,"J202") | strpos(diag_01,"J203") | ///
			strpos(diag_01,"J204") | strpos(diag_01,"J205") | strpos(diag_01,"J206") | strpos(diag_01,"J207") | ///
			strpos(diag_01,"J208") | strpos(diag_01,"J209") | strpos(diag_01,"J22")
			
	/*Other respiratory conditions*/
	replace acsc1st=9 if strpos(diag_01,"E662") | strpos(diag_01,"J80") | strpos(diag_01,"J840") | strpos(diag_01,"J841") | ///
			strpos(diag_01,"J848") | strpos(diag_01,"J849") | strpos(diag_01,"J960") | strpos(diag_01,"J961") | ///
			strpos(diag_01,"J969") | strpos(diag_01,"J980") | strpos(diag_01,"J981") | strpos(diag_01,"J984") | ///	
			strpos(diag_01,"J986") | strpos(diag_01,"J988") | strpos(diag_01,"J989") | strpos(diag_01,"J998") | ///
			strpos(diag_01,"Q340") | strpos(diag_01,"R042") | strpos(diag_01,"R048") | strpos(diag_01,"R05") | ///
			strpos(diag_01,"R060") | strpos(diag_01,"R062") | strpos(diag_01,"R064") | strpos(diag_01,"R098")
			
	/*CHF*/
	replace acsc1st=10 if strpos(diag_01,"I110") | strpos(diag_01,"I130") | strpos(diag_01,"I132") | strpos(diag_01,"I500") | ///
			strpos(diag_01,"I501") | strpos(diag_01,"I509") 
			
	/*Tachycardias*/
	replace acsc1st=11 if strpos(diag_01,"I440") | strpos(diag_01,"I441") | strpos(diag_01,"I444") | strpos(diag_01,"I445") | ///
			strpos(diag_01,"I446") | strpos(diag_01,"I447") | strpos(diag_01,"I450") | strpos(diag_01,"I451") | ///
			strpos(diag_01,"I452") | strpos(diag_01,"I453") | strpos(diag_01,"I454") | strpos(diag_01,"I455") | ///
			strpos(diag_01,"I456") | strpos(diag_01,"I458") | strpos(diag_01,"I459") | strpos(diag_01,"I471") | ///
			strpos(diag_01,"I479") | strpos(diag_01,"I480") | strpos(diag_01,"I481") | strpos(diag_01,"I482") | ///
			strpos(diag_01,"I483") | strpos(diag_01,"I484") | strpos(diag_01,"I489") | strpos(diag_01,"I491") | ///
			strpos(diag_01,"I492") | strpos(diag_01,"I494") | strpos(diag_01,"I495") | strpos(diag_01,"I498") | ///
			strpos(diag_01,"I499") | strpos(diag_01,"R000") | strpos(diag_01,"R001") | strpos(diag_01,"R002") | strpos(diag_01,"R008") 
			
	/*Low risk chest pain*/
	replace acsc1st=12 if strpos(diag_01,"I201") | strpos(diag_01,"I208") | strpos(diag_01,"I209") | strpos(diag_01,"I241") | ///
			strpos(diag_01,"I248") | strpos(diag_01,"I249") | strpos(diag_01,"I250") | strpos(diag_01,"I251") | ///
			strpos(diag_01,"I252") | strpos(diag_01,"I256") | strpos(diag_01,"I258") | strpos(diag_01,"I259") | ///
			strpos(diag_01,"M940") | strpos(diag_01,"M941") | strpos(diag_01,"R011") | strpos(diag_01,"R012") | ///
			strpos(diag_01,"R072") | strpos(diag_01,"R073") | strpos(diag_01,"R074") | strpos(diag_01,"Z034") | ///
			strpos(diag_01,"Z035") 

	/*Transient Ischaemic Attack*/
	replace acsc1st=13 if strpos(diag_01,"G450") | strpos(diag_01,"G451") | strpos(diag_01,"G452") | strpos(diag_01,"G453") | ///
			strpos(diag_01,"G454") | strpos(diag_01,"G458") | strpos(diag_01,"G459") 
			
	/*Stroke*/
	replace acsc1st=14 if strpos(diag_01,"I630") | strpos(diag_01,"I631") | strpos(diag_01,"I632") | strpos(diag_01,"I633") | ///
			strpos(diag_01,"I634") | strpos(diag_01,"I635") | strpos(diag_01,"I636") | strpos(diag_01,"I638") | ///
			strpos(diag_01,"I639") | strpos(diag_01,"I64X") | strpos(diag_01,"I672") | strpos(diag_01,"I679") | ///
			strpos(diag_01,"I698") 

	/*Seizure (first seuzure and seizure in known epileptic)*/
	replace acsc1st=15 if strpos(diag_01,"G253") | strpos(diag_01,"G400") | strpos(diag_01,"G401") | strpos(diag_01,"G402") | ///
			strpos(diag_01,"G403") | strpos(diag_01,"G404") | strpos(diag_01,"G405") | strpos(diag_01,"G406") | ///
			strpos(diag_01,"G407") | strpos(diag_01,"G408") | strpos(diag_01,"G409") | strpos(diag_01,"R568") 
			/*first seuzure and seizure in known epileptic combined as ICD10 code=R568 overlap; 
			this comprises around 50% of seizure cases*/
			
	/*Acute headache*/
	replace acsc1st=16 if strpos(diag_01,"G430") | strpos(diag_01,"G431") | strpos(diag_01,"G432") | strpos(diag_01,"G433") | ///
			strpos(diag_01,"G438") | strpos(diag_01,"G439") | strpos(diag_01,"G440") |  ///
			strpos(diag_01,"G441") | strpos(diag_01,"G443") | strpos(diag_01,"G444") | strpos(diag_01,"G448") |  ///
			strpos(diag_01,"G971") | strpos(diag_01,"R51") 
			
	/*Upper GI haemorrhage*/
	replace acsc1st=17 if strpos(diag_01,"K20") | strpos(diag_01,"K210") | strpos(diag_01,"K219") | strpos(diag_01,"K221") | ///	
			strpos(diag_01,"K226") | strpos(diag_01,"K250") | strpos(diag_01,"K254") | strpos(diag_01,"K256") | ///
			strpos(diag_01,"K260") | strpos(diag_01,"K264") | strpos(diag_01,"K266") | strpos(diag_01,"K270") | ///
			strpos(diag_01,"K274") | strpos(diag_01,"K276") | strpos(diag_01,"K280") | strpos(diag_01,"K284") | ///
			strpos(diag_01,"K286") | strpos(diag_01,"K920") | strpos(diag_01,"K921") | strpos(diag_01,"K922") 
			/*K92.2 comprises 26% of cases*/

	/*Gastroenteritis*/
	replace acsc1st=18 if strpos(diag_01,"A020") | strpos(diag_01,"A022") | strpos(diag_01,"A028") | strpos(diag_01,"A029") | ///
			strpos(diag_01,"A044") | strpos(diag_01,"A045") | strpos(diag_01,"A046") | strpos(diag_01,"A048") | ///
			strpos(diag_01,"A049") | strpos(diag_01,"A054") | strpos(diag_01,"A058") | strpos(diag_01,"A059") | ///
			strpos(diag_01,"A071") | strpos(diag_01,"A072") | strpos(diag_01,"A080") | strpos(diag_01,"A081") | ///
			strpos(diag_01,"A082") | strpos(diag_01,"A083") | strpos(diag_01,"A084") | strpos(diag_01,"A085") | ///
			strpos(diag_01,"A090") | strpos(diag_01,"A099") | strpos(diag_01,"K520") | strpos(diag_01,"K521") | ///
			strpos(diag_01,"K522") | strpos(diag_01,"K528") | strpos(diag_01,"K529") 
		
	/*Inflammatory Bowel Disease*/
	replace acsc1st=19 if strpos(diag_01,"K500") | strpos(diag_01,"K501") | strpos(diag_01,"K508") | strpos(diag_01,"K509") | ///
			strpos(diag_01,"K510") | strpos(diag_01,"K512") | strpos(diag_01,"K513") | strpos(diag_01,"K514") | ///
			strpos(diag_01,"K515") | strpos(diag_01,"K519") | strpos(diag_01,"K523")

	/*Abnormal liver function*/
	replace acsc1st=20 if strpos(diag_01,"C220") | strpos(diag_01,"C221") | strpos(diag_01,"C222") | strpos(diag_01,"C223") | ///
			strpos(diag_01,"C224") | strpos(diag_01,"C227") | strpos(diag_01,"C229") | strpos(diag_01,"C23") | ///
			strpos(diag_01,"C240") | strpos(diag_01,"C241") | strpos(diag_01,"C248") | strpos(diag_01,"C249") | ///
			strpos(diag_01,"C250") | strpos(diag_01,"C251") | strpos(diag_01,"C252") | strpos(diag_01,"C253") | ///
			strpos(diag_01,"C254") | strpos(diag_01,"C257") | strpos(diag_01,"C258") | strpos(diag_01,"C259") | ///
			strpos(diag_01,"C787") | strpos(diag_01,"D135") | strpos(diag_01,"D376") | strpos(diag_01,"K700") | ///
			strpos(diag_01,"K701") | strpos(diag_01,"K702") | strpos(diag_01,"K703") | strpos(diag_01,"K704") | strpos(diag_01,"K709") | ///
			strpos(diag_01,"K720") | strpos(diag_01,"K721") | strpos(diag_01,"K729") | strpos(diag_01,"K730") | strpos(diag_01,"K731") | ///
			strpos(diag_01,"K732") | strpos(diag_01,"K738") | strpos(diag_01,"K739") | strpos(diag_01,"K740") | ///
			strpos(diag_01,"K741") | strpos(diag_01,"K742") | strpos(diag_01,"K743") | strpos(diag_01,"K744") | ///
			strpos(diag_01,"K745") | strpos(diag_01,"K746") | strpos(diag_01,"K752") | strpos(diag_01,"K753") | ///
			strpos(diag_01,"K754") | strpos(diag_01,"K758") | strpos(diag_01,"K759") | strpos(diag_01,"K760") | ///
			strpos(diag_01,"K761") | strpos(diag_01,"K766") | strpos(diag_01,"K768") | strpos(diag_01,"K769") | ///
			strpos(diag_01,"K800") | strpos(diag_01,"K801") | strpos(diag_01,"K802") | strpos(diag_01,"K803") | ///
			strpos(diag_01,"K804") | strpos(diag_01,"K805") | strpos(diag_01,"K808") | strpos(diag_01,"K810") | ///
			strpos(diag_01,"K811") | strpos(diag_01,"K818") | strpos(diag_01,"K819") | strpos(diag_01,"K821") | ///
			strpos(diag_01,"K822") | strpos(diag_01,"K823") | strpos(diag_01,"K824") | strpos(diag_01,"K828") | ///
			strpos(diag_01,"K829") | strpos(diag_01,"K831") | strpos(diag_01,"K834") | strpos(diag_01,"K838") | ///
			strpos(diag_01,"K839") | strpos(diag_01,"K860") | strpos(diag_01,"K861") | strpos(diag_01,"K862") | ///
			strpos(diag_01,"K863") | strpos(diag_01,"K868") | strpos(diag_01,"K869") | strpos(diag_01,"K870") | ///
			strpos(diag_01,"K915") | strpos(diag_01,"R160") | strpos(diag_01,"R161") | strpos(diag_01,"R162") | ///
			strpos(diag_01,"R17") | strpos(diag_01,"R945") 
	 
	 /*Anaemia*/
	replace acsc1st=21 if strpos(diag_01,"D460") | strpos(diag_01,"D461") | strpos(diag_01,"D462") | strpos(diag_01,"D464") | ///
			strpos(diag_01,"D467") | strpos(diag_01,"D469") | strpos(diag_01,"D500") | strpos(diag_01,"D501") | ///
			strpos(diag_01,"D508") | strpos(diag_01,"D509") | strpos(diag_01,"D510") | strpos(diag_01,"D511") | strpos(diag_01,"D512") | ///
			strpos(diag_01,"D513") | strpos(diag_01,"D518") | strpos(diag_01,"D519") | strpos(diag_01,"D520") | ///
			strpos(diag_01,"D521") | strpos(diag_01,"D528") | strpos(diag_01,"D529") | strpos(diag_01,"D531") | ///
			strpos(diag_01,"D571") | strpos(diag_01,"D580") | strpos(diag_01,"D581") | strpos(diag_01,"D582") | ///
			strpos(diag_01,"D588") | strpos(diag_01,"D589") | strpos(diag_01,"D590") | strpos(diag_01,"D591") | ///
			strpos(diag_01,"D592") | strpos(diag_01,"D594") | strpos(diag_01,"D598") | strpos(diag_01,"D599") | ///
			strpos(diag_01,"D648") | strpos(diag_01,"D649") 

	/*Hypoglycaemia*/
	replace acsc1st=22 if strpos(diag_01,"E160") | strpos(diag_01,"E161") | strpos(diag_01,"E162") 

	/*Diabetes*/
	replace acsc1st=23 if strpos(diag_01,"E100") | strpos(diag_01,"E101") | strpos(diag_01,"E102") | ///
			strpos(diag_01,"E103") | strpos(diag_01,"E104") | strpos(diag_01,"E105") | strpos(diag_01,"E106") | ///
			strpos(diag_01,"E107") | strpos(diag_01,"E108") | strpos(diag_01,"E109") | strpos(diag_01,"E110") | ///
			strpos(diag_01,"E111") | strpos(diag_01,"E112") | strpos(diag_01,"E113") | strpos(diag_01,"E114") | ///
			strpos(diag_01,"E115") | strpos(diag_01,"E116") | strpos(diag_01,"E117") | strpos(diag_01,"E118") | ///
			strpos(diag_01,"E119") | strpos(diag_01,"E132") | strpos(diag_01,"E133") | strpos(diag_01,"E134") | ///
			strpos(diag_01,"E135") | strpos(diag_01,"E136") | strpos(diag_01,"E137") | strpos(diag_01,"E138") | ///
			strpos(diag_01,"E139") | strpos(diag_01,"E142") | strpos(diag_01,"E143") | strpos(diag_01,"E144") | ///
			strpos(diag_01,"E145") | strpos(diag_01,"E146") | strpos(diag_01,"E147") | strpos(diag_01,"E148") | ///
			strpos(diag_01,"E149") | strpos(diag_01,"E160") | strpos(diag_01,"E161") | strpos(diag_01,"E162") 
			
	/*Cellulitis of Limb*/
	replace acsc1st=24 if strpos(diag_01,"I891") | strpos(diag_01,"L010") | ///
			strpos(diag_01,"L030") | strpos(diag_01,"L031") | strpos(diag_01,"L032") | strpos(diag_01,"L033") | ///
			strpos(diag_01,"L038") | strpos(diag_01,"L039") | strpos(diag_01,"L080") | strpos(diag_01,"L088") | strpos(diag_01,"L089") 

	/*Known oesophageal stenosis*/
	replace acsc1st=25 if strpos(diag_01,"C150") | strpos(diag_01,"C151") | strpos(diag_01,"C152") | strpos(diag_01,"C153") | ///
			strpos(diag_01,"C154") | strpos(diag_01,"C155") | strpos(diag_01,"C158") | strpos(diag_01,"C159") | ///
			strpos(diag_01,"K220") | strpos(diag_01,"K222") | strpos(diag_01,"K224") | strpos(diag_01,"K225") | ///
			strpos(diag_01,"K227") | strpos(diag_01,"K228") | strpos(diag_01,"K229") | strpos(diag_01,"K238") | ///
			strpos(diag_01,"R12") | strpos(diag_01,"R13") | strpos(diag_01,"T181") 
			
	/*PEG related complications*/
	replace acsc1st=26 if strpos(diag_01,"Z431") | strpos(diag_01,"T855") | strpos(diag_01,"T858") 

	/*Self-harm & Accidental Overdose*/
	replace acsc1st=99 if strpos(diag_01,"T36")  | strpos(diag_01,"T37") | strpos(diag_01,"T38") | strpos(diag_01,"T39") | ///
	strpos(diag_01,"T40") | strpos(diag_01,"T41") | strpos(diag_01,"T42") | strpos(diag_01,"T43") | strpos(diag_01,"T44") | /// 
	strpos(diag_01,"T45") | strpos(diag_01,"T46") | strpos(diag_01,"T47") | strpos(diag_01,"T48") | strpos(diag_01,"T49") | ///
	strpos(diag_01,"T50") | strpos(diag_01,"T51") | strpos(diag_01,"T52") | strpos(diag_01,"T53") | ///
	strpos(diag_01,"T54") | strpos(diag_01,"T55") | strpos(diag_01,"T56") | strpos(diag_01,"T57") | strpos(diag_01,"T58") | ///
	strpos(diag_01,"T59") | strpos(diag_01,"T60") | strpos(diag_01,"T61") | strpos(diag_01,"T62") | strpos(diag_01,"T630") | ///
	strpos(diag_01,"T631") | strpos(diag_01,"T632") | strpos(diag_01,"T633") | strpos(diag_01,"T634") | ///
	strpos(diag_01,"T64") | strpos(diag_01,"T65") | strpos(diag_01,"T68") | strpos(diag_01,"T699")                                              		

	forvalues i = 2(1)9 {
	replace acsc1st=27 if strpos(diag_0`i',"X60") | strpos(diag_0`i',"X61") | strpos(diag_0`i',"X62") | strpos(diag_0`i',"X63") | ///
			strpos(diag_0`i',"X64") | strpos(diag_0`i',"X65") | strpos(diag_0`i',"X66") | strpos(diag_0`i',"X67") | ///
			strpos(diag_0`i',"X68") | strpos(diag_0`i',"X69") & acsc1st==99
	}

	forvalues i = 10(1)20 {
	replace acsc1st=27 if strpos(diag_`i',"X60") | strpos(diag_`i',"X61") | strpos(diag_`i',"X62") | strpos(diag_`i',"X63") | ///
			strpos(diag_`i',"X64") | strpos(diag_`i',"X65") | strpos(diag_`i',"X66") | strpos(diag_`i',"X67") | ///
			strpos(diag_`i',"X68") | strpos(diag_`i',"X69") & acsc1st==99
	}
			
	replace acsc1st=. if acsc1st==99

	/*Falls including syncope or collapse*/
	replace acsc1st=28 if strpos(diag_01,"I951") | strpos(diag_01,"R268") | strpos(diag_01,"R296") | strpos(diag_01,"R54") | ///
			strpos(diag_01,"R55") | strpos(diag_01,"T671")

	/*UTI*/
	replace acsc1st=29 if strpos(diag_01,"N110") | strpos(diag_01,"N111") | strpos(diag_01,"N118") | strpos(diag_01,"N119") | ///
			strpos(diag_01,"N136") | strpos(diag_01,"N300") | strpos(diag_01,"N301") | strpos(diag_01,"N302") | ///
			strpos(diag_01,"N303") | strpos(diag_01,"N304") | strpos(diag_01,"N308") | strpos(diag_01,"N309") | ///
			strpos(diag_01,"N341") | strpos(diag_01,"N342") | strpos(diag_01,"N343") | strpos(diag_01,"N390")
			
	/*Electrolyte Disturbance*/
	replace acsc1st=30 if strpos(diag_01,"E222") | strpos(diag_01,"E612") | strpos(diag_01,"E834") | strpos(diag_01,"E835") | ///
			strpos(diag_01,"E86") | strpos(diag_01,"E870") | strpos(diag_01,"E871") | strpos(diag_01,"E875") | ///
			strpos(diag_01,"E876") | strpos(diag_01,"E877") | strpos(diag_01,"E878")
			
	/*Low-risk acute kidney injury*/
	replace acsc1st=31 if strpos(diag_01,"N178") | strpos(diag_01,"N179") | strpos(diag_01,"N990")
	
	/*Ascites*/
	replace acsc1st=32 if strpos(diag_01,"R18")

	/*Acutely hot painful joint*/
	replace acsc1st=33 if strpos(diag_01,"M020") | strpos(diag_01,"M021") | strpos(diag_01,"M022") | strpos(diag_01,"M023") | ///
			strpos(diag_01,"M028") | strpos(diag_01,"M029") | strpos(diag_01,"M050") | strpos(diag_01,"M058") | ///
			strpos(diag_01,"M059") | strpos(diag_01,"M060") | strpos(diag_01,"M061") | strpos(diag_01,"M062") | strpos(diag_01,"M063") | ///
			strpos(diag_01,"M064") | strpos(diag_01,"M068") | strpos(diag_01,"M069") | strpos(diag_01,"M100") | ///
			strpos(diag_01,"M102") | strpos(diag_01,"M103") | strpos(diag_01,"M104") | strpos(diag_01,"M109") | ///
			strpos(diag_01,"M110") | strpos(diag_01,"M119") | strpos(diag_01,"M130") | strpos(diag_01,"M139") | ///
			strpos(diag_01,"M255") | strpos(diag_01,"M256") | strpos(diag_01,"M259") | strpos(diag_01,"M660") | ///
			strpos(diag_01,"M661") | strpos(diag_01,"M673") | strpos(diag_01,"M712") 

	/*Appendicular fractures not requiring immediate internal fixation*/
	replace acsc1st=34 if strpos(diag_01,"S420") | strpos(diag_01,"S422") | strpos(diag_01,"S423") | strpos(diag_01,"S424") | ///
			strpos(diag_01,"S428") | strpos(diag_01,"S429") | strpos(diag_01,"S430") | strpos(diag_01,"S431") | ///
			strpos(diag_01,"S432") | strpos(diag_01,"S433") | strpos(diag_01,"S520") | strpos(diag_01,"S521") | ///
			strpos(diag_01,"S522") | strpos(diag_01,"S523") | strpos(diag_01,"S524") | strpos(diag_01,"S525") | ///
			strpos(diag_01,"S526") | strpos(diag_01,"S527") | strpos(diag_01,"S528") | strpos(diag_01,"S529") | ///
			strpos(diag_01,"S530") | strpos(diag_01,"S531") | strpos(diag_01,"S532") | strpos(diag_01,"S533") | ///
			strpos(diag_01,"S620") | strpos(diag_01,"S621") | strpos(diag_01,"S622") | strpos(diag_01,"S623") | ///
			strpos(diag_01,"S624") | strpos(diag_01,"S625") | strpos(diag_01,"S626") | strpos(diag_01,"S627") | ///
			strpos(diag_01,"S628") | strpos(diag_01,"S630") | strpos(diag_01,"S632") | strpos(diag_01,"S670") | ///
			strpos(diag_01,"S678") | strpos(diag_01,"S724") | strpos(diag_01,"S820") | strpos(diag_01,"S821") | ///
			strpos(diag_01,"S822") | strpos(diag_01,"S823") | strpos(diag_01,"S824") | strpos(diag_01,"S825") | ///
			strpos(diag_01,"S826") | strpos(diag_01,"S828") | strpos(diag_01,"S829") | strpos(diag_01,"S830") | ///
			strpos(diag_01,"S831") | strpos(diag_01,"S832") | strpos(diag_01,"S920") | strpos(diag_01,"S921") | ///
			strpos(diag_01,"S922") | strpos(diag_01,"S923") | strpos(diag_01,"S924") | strpos(diag_01,"S925") | ///
			strpos(diag_01,"S927") | strpos(diag_01,"S929") | strpos(diag_01,"S930") | strpos(diag_01,"S931") | ///
			strpos(diag_01,"S971") 
	 
	/*Non-traumatic vertebral fractures*/
	replace acsc1st=35 if strpos(diag_01,"M800") | strpos(diag_01,"M801") | strpos(diag_01,"M802") | strpos(diag_01,"M803") | ///
			strpos(diag_01,"M804") | strpos(diag_01,"M805") | strpos(diag_01,"M808") | strpos(diag_01,"M809") | ///
			strpos(diag_01,"M843") | strpos(diag_01,"M844") 
			
	/*Low risk pubic rami fractures*/
	replace acsc1st=36 if strpos(diag_01,"S325") 
				
	/*Hip pain secondary to a fall and non weight bearing*/
	replace acsc1st=37 if strpos(diag_01,"S760") | strpos(diag_01,"M255") 
	
	/*Lower GI haemorrage*/
	replace acsc1st=38 if strpos(diag_01,"K625") | strpos(diag_01,"K922") 
	
	/*Obstructive jaundice*/
	replace acsc1st=39 if strpos(diag_01,"C23") | strpos(diag_01,"C240") | strpos(diag_01,"C241") | strpos(diag_01,"C248") | ///
			strpos(diag_01,"C249") | strpos(diag_01,"C250") | strpos(diag_01,"C251") | strpos(diag_01,"C253") | ///		
			strpos(diag_01,"C259") | strpos(diag_01,"D135") | strpos(diag_01,"D376") | strpos(diag_01,"K805") | ///	
			strpos(diag_01,"K821") | strpos(diag_01,"K822") | strpos(diag_01,"K823") | strpos(diag_01,"K824") | ///
			strpos(diag_01,"K828") | strpos(diag_01,"K829") | strpos(diag_01,"K831") | strpos(diag_01,"K839") | ///
			strpos(diag_01,"K870") | strpos(diag_01,"R17")
			
	/*Acute abdominal pain not requiring operative intervention*/
	replace acsc1st=40 if strpos(diag_01,"I880") | strpos(diag_01,"K297") | strpos(diag_01,"K563") | strpos(diag_01,"K564") | strpos(diag_01,"K566") | ///
			strpos(diag_01,"K590") | strpos(diag_01,"K591") | strpos(diag_01,"K598") | strpos(diag_01,"K599") | strpos(diag_01,"K913") | ///
			strpos(diag_01,"N832") | strpos(diag_01,"N940") | strpos(diag_01,"R101") | strpos(diag_01,"R102") | strpos(diag_01,"R103") | strpos(diag_01,"R104") | ///		
			strpos(diag_01,"R11") | strpos(diag_01,"R190") | strpos(diag_01,"R191") | strpos(diag_01,"R194") | strpos(diag_01,"R195") | ///	
			strpos(diag_01,"R198")  
			
	/*Abscesses requiring surgical drainage - perianal, breast wound*/
	replace acsc1st=41 if strpos(diag_01,"K610") | strpos(diag_01,"K612") | strpos(diag_01,"K613") | strpos(diag_01,"K614") | ///
			strpos(diag_01,"K620") | strpos(diag_01,"L020") | strpos(diag_01,"L021") | strpos(diag_01,"L022") | strpos(diag_01,"L023") | ///
			strpos(diag_01,"L024") | strpos(diag_01,"L028") | strpos(diag_01,"L029") | strpos(diag_01,"L050") | strpos(diag_01,"L059") | ///
			strpos(diag_01,"L720") | strpos(diag_01,"L721") | strpos(diag_01,"N61") 	

	/*Head injury*/
	replace acsc1st=42 if strpos(diag_01,"S060") | strpos(diag_01,"S098") | strpos(diag_01,"S099") 

	/*Right upper quadrant pain*/
	replace acsc1st=43 if strpos(diag_01,"K563") | strpos(diag_01,"K820") | strpos(diag_01,"K830") | strpos(diag_01,"K800") | ///
			strpos(diag_01,"K801") | strpos(diag_01,"K802") | strpos(diag_01,"K803") | strpos(diag_01,"K804") | strpos(diag_01,"K808") | ///
			strpos(diag_01,"K810") | strpos(diag_01,"K811") | strpos(diag_01,"K818") | strpos(diag_01,"K819") | strpos(diag_01,"K831") | ///
			strpos(diag_01,"K839") | strpos(diag_01,"K824") | strpos(diag_01,"K828") | strpos(diag_01,"K829") | strpos(diag_01,"K838") | strpos(diag_01,"K870")
			
	/*Painful non-obstructed hernia*/
	replace acsc1st=44 if strpos(diag_01,"K402") | strpos(diag_01,"K409") | strpos(diag_01,"K412") | strpos(diag_01,"K419") | ///
			strpos(diag_01,"K429") | strpos(diag_01,"K432") | strpos(diag_01,"K435") | strpos(diag_01,"K439") | ///
			strpos(diag_01,"K458") | strpos(diag_01,"K469")
			
	/*Haemorrhoids*/
	replace acsc1st=45 if strpos(diag_01,"K640") | strpos(diag_01,"K641") | strpos(diag_01,"K642") | strpos(diag_01,"K643") | ///
			strpos(diag_01,"K648") | strpos(diag_01,"K649") | strpos(diag_01,"O224") | strpos(diag_01,"O872") 
			
	/*Right iliac fossa pain*/
	replace acsc1st=46 if strpos(diag_01,"K353") | strpos(diag_01,"K358") | strpos(diag_01,"K37") | strpos(diag_01,"K500")
	
	/*Left iliac fossa pain*/
	replace acsc1st=47 if strpos(diag_01,"K562") | strpos(diag_01,"K571") | strpos(diag_01,"K573") | strpos(diag_01,"K575")	| strpos(diag_01,"K579") | strpos(diag_01,"N739")	
	
	/*Other anorectal issues*/
	replace acsc1st=48 if strpos(diag_01,"K594") | strpos(diag_01,"K600") | strpos(diag_01,"K601") | strpos(diag_01,"K602")	| strpos(diag_01,"K603") | strpos(diag_01,"K605") | strpos(diag_01,"T185")
	
	/*Acute painful bladder outflow obstruction*/
	replace acsc1st=49 if strpos(diag_01,"N393") | strpos(diag_01,"N394") | strpos(diag_01,"R32") | strpos(diag_01,"R33") | ///
			strpos(diag_01,"R391") | strpos(diag_01,"N320") | strpos(diag_01,"N40") | strpos(diag_01,"N428") | strpos(diag_01,"N429")
			
	/*Renal/ureteric stones*/
	replace acsc1st=50 if strpos(diag_01,"N200") | strpos(diag_01,"N201") | strpos(diag_01,"N202") | strpos(diag_01,"N209") | ///
			strpos(diag_01,"N210") | strpos(diag_01,"N211") | strpos(diag_01,"N218") | strpos(diag_01,"N219") | ///
			strpos(diag_01,"N23")
	 
	/*Gross haematuria*/
	replace acsc1st=51 if strpos(diag_01,"R300") | strpos(diag_01,"R309") | strpos(diag_01,"R31") 

	/*Chronic indwelling catheter related problems*/
	replace acsc1st=52 if strpos(diag_01,"T830") | strpos(diag_01,"T831") | strpos(diag_01,"T835") | strpos(diag_01,"T836") | ///
			strpos(diag_01,"T838") | strpos(diag_01,"T839") 
			
	/*Acute scrotal pain*/
	replace acsc1st=53 if strpos(diag_01,"N430") | strpos(diag_01,"N431") | strpos(diag_01,"N432") | strpos(diag_01,"N433") | ///
			strpos(diag_01,"N434") | strpos(diag_01,"N44") | strpos(diag_01,"N450") | strpos(diag_01,"N459") | ///
			strpos(diag_01,"N490") | strpos(diag_01,"N491") | strpos(diag_01,"N492") | strpos(diag_01,"N498") | ///
			strpos(diag_01,"N499") | strpos(diag_01,"N508") 
			
	/*Early bleeding pregnancy*/
	replace acsc1st=54 if strpos(diag_01,"O020") | strpos(diag_01,"O021") | strpos(diag_01,"O028") | strpos(diag_01,"O029") | ///
			strpos(diag_01,"O03") | strpos(diag_01,"O054") | strpos(diag_01,"O059") | strpos(diag_01,"O064") | ///
			strpos(diag_01,"O069") | strpos(diag_01,"O200") | strpos(diag_01,"O208") | strpos(diag_01,"O209")
			
	/*Ectopic pregnancy*/
	replace acsc1st=55 if strpos(diag_01,"O001") | strpos(diag_01,"O002") | strpos(diag_01,"O008") | strpos(diag_01,"O009")
	
	/*Hyperemesis gravidarum*/
	replace acsc1st=56 if strpos(diag_01,"O210") | strpos(diag_01,"O211") | strpos(diag_01,"O212") | strpos(diag_01,"O218") | strpos(diag_01,"O219")
	
	/*Diseases of Bartholin's gland*/
	replace acsc1st=57 if strpos(diag_01,"N750") | strpos(diag_01,"N751") | strpos(diag_01,"N758") | strpos(diag_01,"N759")
	
	
	label define acsc1st_lbl 	1 "deep vein thrombosis" ///
						2 "pulmonary embolism" ///
						3 "pneumothorax" ///
						4 "pleural effusions" ///
						5 "asthma" ///
						6 "COPD" ///
						7 "community acquired pneumonia" ///
						8 "LRTI without COPD" ///
						9 "Other respiratory conditions" ///
						10 "CHF" ///
						11 "tachycardias" ///
						12 "low risk chest pain" ///
						13 "Transient ischaemic attack" ///
						14 "stroke" ///
						15 "seizure" ///
						16 "acute headache" ///
						17 "upper GI haemorrhage" ///
						18 "gastroenteritis" ///
						19 "inflammatory bowel disease" ///
						20 "abnormal liver function" ///
						21 "anaemia" ///
						22 "hypoglycaemia" ///
						23 "diabetes" ///
						24 "cellulitis of limb" ///
						25 "known oesophageal stenosis" ///
						26 "PEG related complications" ///
						27 "self-harm & accidental overdose" ///
						28 "falls" ///
						29 "UTI" ///
						30 "Electrolyte disturbance" ///
						31 "Low risk acute kidney injury" ///
						32 "Ascites" ///
						33 "acutely hot painful joint" ///
						34 "appendicular fractures" ///
						35 "non-traumatic vertebral fractures" ///
						36 "low risk pubic rami fractures" ///
						37 "hip pain secondary to fall" ///
						38 "lower GI haemorrage" ///
						39 "obstructive jaundice" ///
						40 "acute abdominal pain" ///
						41 "abscess requiring drainage" ///
						42 "head injury" ///
						43 "right upper quadrant pain" ///
						44 "painful non-obstructed hernia" ///
						45 "Haemorrhoids" ///
						46 "right iliac fossa pain" ///
						47 "left iliac fossa pain" ///
						48 "other anorectal issues" ///
						49 "acute painful bladder outflow obstruction" ///
						50 "renal/uteric stones" ///
						51 "gross haematuria" ///
						52 "Chronic indwelling catheter related problems" ///
						53 "Acute scrotal pain" ///
						54 "Early bleeding pregnancy" ///
						55 "Ectopic pregnancy" ///
						56 "Hyperemesis gravidarum" ///
						57 "Diseases of Bartholin's gland"
					
	label val acsc1st acsc1st_lbl	
	
	*******************************************
	
	*** Check for the Charlson Comorbidities (based on Quan et al. (2005) ICD-10 codes in any diagnosis position) ***
	
	* Myocardial Infarction
	gen comorb_mi = 0
	forvalues i = 1(1)9 {
		replace comorb_mi = 1 if strpos(diag_0`i',"I21") | strpos(diag_0`i',"I22") | strpos(diag_0`i',"I252")
	}

	forvalues i = 10(1)20 {
		replace comorb_mi = 1 if strpos(diag_`i',"I21") | strpos(diag_`i',"I22") | strpos(diag_`i',"I252")
	}
	
	* Congestive heart failure
	gen comorb_chf = 0
	forvalues i = 1(1)9 {
		replace comorb_chf = 1 if strpos(diag_0`i',"I099") | strpos(diag_0`i',"I110") | strpos(diag_0`i',"I130") | strpos(diag_0`i',"I132") | strpos(diag_0`i',"I255") ///
		| strpos(diag_0`i',"I420") | strpos(diag_0`i',"I425") | strpos(diag_0`i',"I426") | strpos(diag_0`i',"I427") | strpos(diag_0`i',"I428") | strpos(diag_0`i',"I429") ///
		| strpos(diag_0`i',"I43") | strpos(diag_0`i',"I50") | strpos(diag_0`i',"P290")
	}

	forvalues i = 10(1)20 {
		replace comorb_chf = 1 if strpos(diag_`i',"I099") | strpos(diag_`i',"I110") | strpos(diag_`i',"I130") | strpos(diag_`i',"I132") | strpos(diag_`i',"I255") ///
		| strpos(diag_`i',"I420") | strpos(diag_`i',"I425") | strpos(diag_`i',"I426") | strpos(diag_`i',"I427") | strpos(diag_`i',"I428") | strpos(diag_`i',"I429") ///
		| strpos(diag_`i',"I43") | strpos(diag_`i',"I50") | strpos(diag_`i',"P290")
	}	
	
	* Peripheral Vascular Disease
	gen comorb_pvd = 0
	forvalues i = 1(1)9 {
		replace comorb_pvd = 1 if strpos(diag_0`i',"I70") | strpos(diag_0`i',"I71") | strpos(diag_0`i',"I731") | strpos(diag_0`i',"I738") | strpos(diag_0`i',"I739") ///
		| strpos(diag_0`i',"I771") | strpos(diag_0`i',"I790") | strpos(diag_0`i',"I792") | strpos(diag_0`i',"K551") | strpos(diag_0`i',"K558") | strpos(diag_0`i',"K559") ///
		| strpos(diag_0`i',"Z958") | strpos(diag_0`i',"Z959")
	}

	forvalues i = 10(1)20 {
		replace comorb_pvd = 1 if strpos(diag_`i',"I70") | strpos(diag_`i',"I71") | strpos(diag_`i',"I731") | strpos(diag_`i',"I738") | strpos(diag_`i',"I739") ///
		| strpos(diag_`i',"I771") | strpos(diag_`i',"I790") | strpos(diag_`i',"I792") | strpos(diag_`i',"K551") | strpos(diag_`i',"K558") | strpos(diag_`i',"K559") ///
		| strpos(diag_`i',"Z958") | strpos(diag_`i',"Z959")
	}
	
	* Cerebrovascular Disease
	gen comorb_cvd = 0
	forvalues i = 1(1)9 {
		replace comorb_cvd = 1 if strpos(diag_0`i',"G45") | strpos(diag_0`i',"G46") | strpos(diag_0`i',"H340") | strpos(diag_0`i',"I6")
	}

	forvalues i = 10(1)20 {
		replace comorb_cvd = 1 if strpos(diag_`i',"G45") | strpos(diag_`i',"G46") | strpos(diag_`i',"H340") | strpos(diag_`i',"I6")
	}
	
	* Dementia
	gen comorb_dem = 0
	forvalues i = 1(1)9 {
		replace comorb_dem = 1 if strpos(diag_0`i',"F00") | strpos(diag_0`i',"F01") | strpos(diag_0`i',"F02") | strpos(diag_0`i',"F03") | strpos(diag_0`i',"F051") | strpos(diag_0`i',"G30") | strpos(diag_0`i',"G311")
	}

	forvalues i = 10(1)20 {
		replace comorb_dem = 1 if strpos(diag_`i',"F00") | strpos(diag_`i',"F01") | strpos(diag_`i',"F02") | strpos(diag_`i',"F03") | strpos(diag_`i',"F051") | strpos(diag_`i',"G30") | strpos(diag_`i',"G311")
	}	
	
	* Chronic Pulmonary Disease
	gen comorb_cpd = 0
	forvalues i = 1(1)9 {
		replace comorb_cpd = 1 if strpos(diag_0`i',"I278") | strpos(diag_0`i',"I279") | strpos(diag_0`i',"J40") | strpos(diag_0`i',"J41") | strpos(diag_0`i',"J42") | strpos(diag_0`i',"J43") | strpos(diag_0`i',"J44") ///
		| strpos(diag_0`i',"J45") | strpos(diag_0`i',"J46") | strpos(diag_0`i',"J47") | strpos(diag_0`i',"J60") | strpos(diag_0`i',"J61") | strpos(diag_0`i',"J62") | strpos(diag_0`i',"J63") | strpos(diag_0`i',"J64") ///
		| strpos(diag_0`i',"J65") | strpos(diag_0`i',"J66") | strpos(diag_0`i',"J67") | strpos(diag_0`i',"J684") | strpos(diag_0`i',"J701") | strpos(diag_0`i',"J703")
	}

	forvalues i = 10(1)20 {
		replace comorb_cpd = 1 if strpos(diag_`i',"I278") | strpos(diag_`i',"I279") | strpos(diag_`i',"J40") | strpos(diag_`i',"J41") | strpos(diag_`i',"J42") | strpos(diag_`i',"J43") | strpos(diag_`i',"J44") ///
		| strpos(diag_`i',"J45") | strpos(diag_`i',"J46") | strpos(diag_`i',"J47") | strpos(diag_`i',"J60") | strpos(diag_`i',"J61") | strpos(diag_`i',"J62") | strpos(diag_`i',"J63") | strpos(diag_`i',"J64") ///
		| strpos(diag_`i',"J65") | strpos(diag_`i',"J66") | strpos(diag_`i',"J67") | strpos(diag_`i',"J684") | strpos(diag_`i',"J701") | strpos(diag_`i',"J703")
	}	
	
	* Rheumatic Disease
	gen comorb_rhe = 0
	forvalues i = 1(1)9 {
		replace comorb_rhe = 1 if strpos(diag_0`i',"M05") | strpos(diag_0`i',"M06") | strpos(diag_0`i',"M315") | strpos(diag_0`i',"M32") | strpos(diag_0`i',"M33") | strpos(diag_0`i',"M34") | strpos(diag_0`i',"M351") ///
		| strpos(diag_0`i',"M353") | strpos(diag_0`i',"M360")
	}

	forvalues i = 10(1)20 {
		replace comorb_rhe = 1 if strpos(diag_`i',"M05") | strpos(diag_`i',"M06") | strpos(diag_`i',"M315") | strpos(diag_`i',"M32") | strpos(diag_`i',"M33") | strpos(diag_`i',"M34") | strpos(diag_`i',"M351") ///
		| strpos(diag_`i',"M353") | strpos(diag_`i',"M360")
	}	
	
	* Peptic Ulcer Disease
	gen comorb_pud = 0
	forvalues i = 1(1)9 {
		replace comorb_pud = 1 if strpos(diag_0`i',"K25") | strpos(diag_0`i',"K26") | strpos(diag_0`i',"K27") | strpos(diag_0`i',"K28") 
	}

	forvalues i = 10(1)20 {
		replace comorb_pud = 1 if strpos(diag_`i',"K25") | strpos(diag_`i',"K26") | strpos(diag_`i',"K27") | strpos(diag_`i',"K28")
	}	
	
	* Mild Liver Disease
	gen comorb_mld = 0
	forvalues i = 1(1)9 {
		replace comorb_mld = 1 if strpos(diag_0`i',"B18") | strpos(diag_0`i',"K700") | strpos(diag_0`i',"K701") | strpos(diag_0`i',"K702") | strpos(diag_0`i',"K703") | strpos(diag_0`i',"K709") | strpos(diag_0`i',"K713") ///
		| strpos(diag_0`i',"K714") | strpos(diag_0`i',"K715") | strpos(diag_0`i',"K717") | strpos(diag_0`i',"K73") | strpos(diag_0`i',"K74") | strpos(diag_0`i',"K760") | strpos(diag_0`i',"K762") | strpos(diag_0`i',"K763") ///
		| strpos(diag_0`i',"K764") | strpos(diag_0`i',"K768") | strpos(diag_0`i',"K769") | strpos(diag_0`i',"Z944")
	}

	forvalues i = 10(1)20 {
		replace comorb_mld = 1 if strpos(diag_`i',"B18") | strpos(diag_`i',"K700") | strpos(diag_`i',"K701") | strpos(diag_`i',"K702") | strpos(diag_`i',"K703") | strpos(diag_`i',"K709") | strpos(diag_`i',"K713") ///
		| strpos(diag_`i',"K714") | strpos(diag_`i',"K715") | strpos(diag_`i',"K717") | strpos(diag_`i',"K73") | strpos(diag_`i',"K74") | strpos(diag_`i',"K760") | strpos(diag_`i',"K762") | strpos(diag_`i',"K763") ///
		| strpos(diag_`i',"K764") | strpos(diag_`i',"K768") | strpos(diag_`i',"K769") | strpos(diag_`i',"Z944")
	}	
	
	* Diabetes without Chronic Complications
	gen comorb_dmnocc = 0
	forvalues i = 1(1)9 {
		replace comorb_dmnocc = 1 if strpos(diag_0`i',"E100") | strpos(diag_0`i',"E101") | strpos(diag_0`i',"E106") | strpos(diag_0`i',"E108") | strpos(diag_0`i',"E109") | strpos(diag_0`i',"E110") | strpos(diag_0`i',"E111") ///
		| strpos(diag_0`i',"E116") | strpos(diag_0`i',"E118") | strpos(diag_0`i',"E119") | strpos(diag_0`i',"E120") | strpos(diag_0`i',"E121") | strpos(diag_0`i',"KE126") | strpos(diag_0`i',"E128") | strpos(diag_0`i',"E129") ///
		| strpos(diag_0`i',"E130") | strpos(diag_0`i',"E131") | strpos(diag_0`i',"E136") | strpos(diag_0`i',"E138") | strpos(diag_0`i',"E139") | strpos(diag_0`i',"E140") | strpos(diag_0`i',"E141") | strpos(diag_0`i',"E146") ///
		| strpos(diag_0`i',"E148") | strpos(diag_0`i',"E149")
	}

	forvalues i = 10(1)20 {
		replace comorb_dmnocc = 1 if strpos(diag_`i',"E100") | strpos(diag_`i',"E101") | strpos(diag_`i',"E106") | strpos(diag_`i',"E108") | strpos(diag_`i',"E109") | strpos(diag_`i',"E110") | strpos(diag_`i',"E111") ///
		| strpos(diag_`i',"E116") | strpos(diag_`i',"E118") | strpos(diag_`i',"E119") | strpos(diag_`i',"E120") | strpos(diag_`i',"E121") | strpos(diag_`i',"KE126") | strpos(diag_`i',"E128") | strpos(diag_`i',"E129") ///
		| strpos(diag_`i',"E130") | strpos(diag_`i',"E131") | strpos(diag_`i',"E136") | strpos(diag_`i',"E138") | strpos(diag_`i',"E139") | strpos(diag_`i',"E140") | strpos(diag_`i',"E141") | strpos(diag_`i',"E146") ///
		| strpos(diag_`i',"E148") | strpos(diag_`i',"E149")
	}
	
	* Diabetes *with* Chronic Complications
	gen comorb_dmcc = 0
	forvalues i = 1(1)9 {
		replace comorb_dmcc = 1 if strpos(diag_0`i',"E102") | strpos(diag_0`i',"E103") | strpos(diag_0`i',"E104") | strpos(diag_0`i',"E105") | strpos(diag_0`i',"E107") | strpos(diag_0`i',"E112") | strpos(diag_0`i',"E113") ///
		| strpos(diag_0`i',"E114") | strpos(diag_0`i',"E115") | strpos(diag_0`i',"E117") | strpos(diag_0`i',"E122") | strpos(diag_0`i',"E123") | strpos(diag_0`i',"KE124") | strpos(diag_0`i',"E125") | strpos(diag_0`i',"E127") ///
		| strpos(diag_0`i',"E132") | strpos(diag_0`i',"E133") | strpos(diag_0`i',"E134") | strpos(diag_0`i',"E135") | strpos(diag_0`i',"E137") | strpos(diag_0`i',"E142") | strpos(diag_0`i',"E143") | strpos(diag_0`i',"E144") ///
		| strpos(diag_0`i',"E145") | strpos(diag_0`i',"E147")
	}

	forvalues i = 10(1)20 {
		replace comorb_dmcc = 1 if strpos(diag_`i',"E102") | strpos(diag_`i',"E103") | strpos(diag_`i',"E104") | strpos(diag_`i',"E105") | strpos(diag_`i',"E107") | strpos(diag_`i',"E112") | strpos(diag_`i',"E113") ///
		| strpos(diag_`i',"E114") | strpos(diag_`i',"E115") | strpos(diag_`i',"E117") | strpos(diag_`i',"E122") | strpos(diag_`i',"E123") | strpos(diag_`i',"KE124") | strpos(diag_`i',"E125") | strpos(diag_`i',"E127") ///
		| strpos(diag_`i',"E132") | strpos(diag_`i',"E133") | strpos(diag_`i',"E134") | strpos(diag_`i',"E135") | strpos(diag_`i',"E137") | strpos(diag_`i',"E142") | strpos(diag_`i',"E143") | strpos(diag_`i',"E144") ///
		| strpos(diag_`i',"E145") | strpos(diag_`i',"E147")
	}
	
	* Hemiplegia or paraplegia
	gen comorb_hppp = 0
	forvalues i = 1(1)9 {
		replace comorb_hppp = 1 if strpos(diag_0`i',"G041") | strpos(diag_0`i',"G114") | strpos(diag_0`i',"G801") | strpos(diag_0`i',"G802") | strpos(diag_0`i',"G81") | strpos(diag_0`i',"G82") | strpos(diag_0`i',"G830") ///
		| strpos(diag_0`i',"G831") | strpos(diag_0`i',"G832") | strpos(diag_0`i',"G833") | strpos(diag_0`i',"G834") | strpos(diag_0`i',"G839")
	}

	forvalues i = 10(1)20 {
		replace comorb_hppp = 1 if strpos(diag_`i',"G041") | strpos(diag_`i',"G114") | strpos(diag_`i',"G801") | strpos(diag_`i',"G802") | strpos(diag_`i',"G81") | strpos(diag_`i',"G82") | strpos(diag_`i',"G830") ///
		| strpos(diag_`i',"G831") | strpos(diag_`i',"G832") | strpos(diag_`i',"G833") | strpos(diag_`i',"G834") | strpos(diag_`i',"G839")
	}	
	
	* Renal Disease
	gen comorb_ren = 0
	forvalues i = 1(1)9 {
		replace comorb_ren = 1 if strpos(diag_0`i',"I120") | strpos(diag_0`i',"I131") | strpos(diag_0`i',"N032") | strpos(diag_0`i',"N033") | strpos(diag_0`i',"N034") | strpos(diag_0`i',"N035") | strpos(diag_0`i',"N036") ///
		| strpos(diag_0`i',"N037") | strpos(diag_0`i',"N052") | strpos(diag_0`i',"N053") | strpos(diag_0`i',"N054") | strpos(diag_0`i',"N055") | strpos(diag_0`i',"N056") | strpos(diag_0`i',"N057") | strpos(diag_0`i',"N18") ///
		| strpos(diag_0`i',"N19") | strpos(diag_0`i',"N250") | strpos(diag_0`i',"Z490") | strpos(diag_0`i',"Z491") | strpos(diag_0`i',"Z492") | strpos(diag_0`i',"Z940") | strpos(diag_0`i',"Z992")
	}

	forvalues i = 10(1)20 {
		replace comorb_ren = 1 if strpos(diag_`i',"I120") | strpos(diag_`i',"I131") | strpos(diag_`i',"N032") | strpos(diag_`i',"N033") | strpos(diag_`i',"N034") | strpos(diag_`i',"N035") | strpos(diag_`i',"N036") ///
		| strpos(diag_`i',"N037") | strpos(diag_`i',"N052") | strpos(diag_`i',"N053") | strpos(diag_`i',"N054") | strpos(diag_`i',"N055") | strpos(diag_`i',"N056") | strpos(diag_`i',"N057") | strpos(diag_`i',"N18") ///
		| strpos(diag_`i',"N19") | strpos(diag_`i',"N250") | strpos(diag_`i',"Z490") | strpos(diag_`i',"Z491") | strpos(diag_`i',"Z492") | strpos(diag_`i',"Z940") | strpos(diag_`i',"Z992")
	}	
	
	* Any Malignancy
	gen comorb_mal = 0
	forvalues i = 1(1)9 {
		replace comorb_mal = 1 if strpos(diag_0`i',"C0") | strpos(diag_0`i',"C1") | strpos(diag_0`i',"C20") | strpos(diag_0`i',"C21") | strpos(diag_0`i',"C22") | strpos(diag_0`i',"C23") | strpos(diag_0`i',"C24") ///
		| strpos(diag_0`i',"C25") | strpos(diag_0`i',"C26") | strpos(diag_0`i',"C30") | strpos(diag_0`i',"C31") | strpos(diag_0`i',"C32") | strpos(diag_0`i',"C33") | strpos(diag_0`i',"C34") | strpos(diag_0`i',"C37") ///
		| strpos(diag_0`i',"C38") | strpos(diag_0`i',"C39") | strpos(diag_0`i',"C40") | strpos(diag_0`i',"C41") | strpos(diag_0`i',"C43") | strpos(diag_0`i',"C45") | strpos(diag_0`i',"C46") | strpos(diag_0`i',"C47") ///
		| strpos(diag_0`i',"C48") | strpos(diag_0`i',"C49") | strpos(diag_0`i',"C50") | strpos(diag_0`i',"C51") | strpos(diag_0`i',"C52") | strpos(diag_0`i',"C53") | strpos(diag_0`i',"C54") | strpos(diag_0`i',"C55") ///
		| strpos(diag_0`i',"C56") | strpos(diag_0`i',"C57") | strpos(diag_0`i',"C58") | strpos(diag_0`i',"C6") | strpos(diag_0`i',"C70") | strpos(diag_0`i',"C71") | strpos(diag_0`i',"C72") | strpos(diag_0`i',"C73") ///
		| strpos(diag_0`i',"C74") | strpos(diag_0`i',"C75") | strpos(diag_0`i',"C76") | strpos(diag_0`i',"C81") | strpos(diag_0`i',"C82") | strpos(diag_0`i',"C83") | strpos(diag_0`i',"C84") | strpos(diag_0`i',"C85") ///
		| strpos(diag_0`i',"C88") | strpos(diag_0`i',"C90") | strpos(diag_0`i',"C91") | strpos(diag_0`i',"C92") | strpos(diag_0`i',"C93") | strpos(diag_0`i',"C94") | strpos(diag_0`i',"C95") | strpos(diag_0`i',"C96") ///
		| strpos(diag_0`i',"C97")
	}

	forvalues i = 10(1)20 {
		replace comorb_mal = 1 if strpos(diag_`i',"C0") | strpos(diag_`i',"C1") | strpos(diag_`i',"C20") | strpos(diag_`i',"C21") | strpos(diag_`i',"C22") | strpos(diag_`i',"C23") | strpos(diag_`i',"C24") ///
		| strpos(diag_`i',"C25") | strpos(diag_`i',"C26") | strpos(diag_`i',"C30") | strpos(diag_`i',"C31") | strpos(diag_`i',"C32") | strpos(diag_`i',"C33") | strpos(diag_`i',"C34") | strpos(diag_`i',"C37") ///
		| strpos(diag_`i',"C38") | strpos(diag_`i',"C39") | strpos(diag_`i',"C40") | strpos(diag_`i',"C41") | strpos(diag_`i',"C43") | strpos(diag_`i',"C45") | strpos(diag_`i',"C46") | strpos(diag_`i',"C47") ///
		| strpos(diag_`i',"C48") | strpos(diag_`i',"C49") | strpos(diag_`i',"C50") | strpos(diag_`i',"C51") | strpos(diag_`i',"C52") | strpos(diag_`i',"C53") | strpos(diag_`i',"C54") | strpos(diag_`i',"C55") ///
		| strpos(diag_`i',"C56") | strpos(diag_`i',"C57") | strpos(diag_`i',"C58") | strpos(diag_`i',"C6") | strpos(diag_`i',"C70") | strpos(diag_`i',"C71") | strpos(diag_`i',"C72") | strpos(diag_`i',"C73") ///
		| strpos(diag_`i',"C74") | strpos(diag_`i',"C75") | strpos(diag_`i',"C76") | strpos(diag_`i',"C81") | strpos(diag_`i',"C82") | strpos(diag_`i',"C83") | strpos(diag_`i',"C84") | strpos(diag_`i',"C85") ///
		| strpos(diag_`i',"C88") | strpos(diag_`i',"C90") | strpos(diag_`i',"C91") | strpos(diag_`i',"C92") | strpos(diag_`i',"C93") | strpos(diag_`i',"C94") | strpos(diag_`i',"C95") | strpos(diag_`i',"C96") ///
		| strpos(diag_`i',"C97")
	}	
	
	* Moderate or Severe Liver Disease
	gen comorb_sld = 0
	forvalues i = 1(1)9 {
		replace comorb_sld = 1 if strpos(diag_0`i',"I850") | strpos(diag_0`i',"I859") | strpos(diag_0`i',"I864") | strpos(diag_0`i',"I982") | strpos(diag_0`i',"K704") | strpos(diag_0`i',"K711") | strpos(diag_0`i',"K721") ///
		| strpos(diag_0`i',"K729") | strpos(diag_0`i',"K765") | strpos(diag_0`i',"K766") | strpos(diag_0`i',"K767")
	}

	forvalues i = 10(1)20 {
		replace comorb_sld = 1 if strpos(diag_`i',"I850") | strpos(diag_`i',"I859") | strpos(diag_`i',"I864") | strpos(diag_`i',"I982") | strpos(diag_`i',"K704") | strpos(diag_`i',"K711") | strpos(diag_`i',"K721") ///
		| strpos(diag_`i',"K729") | strpos(diag_`i',"K765") | strpos(diag_`i',"K766") | strpos(diag_`i',"K767")
	}	
	
	* Metastatic Solid Tumour
	gen comorb_mst = 0
	forvalues i = 1(1)9 {
		replace comorb_mst = 1 if strpos(diag_0`i',"C77") | strpos(diag_0`i',"C78") | strpos(diag_0`i',"C79") | strpos(diag_0`i',"C80")
	}

	forvalues i = 10(1)20 {
		replace comorb_mst = 1 if strpos(diag_`i',"C77") | strpos(diag_`i',"C78") | strpos(diag_`i',"C79") | strpos(diag_`i',"C80")
	}
	
	* AIDS/HIV
	gen comorb_hiv = 0
	forvalues i = 1(1)9 {
		replace comorb_hiv = 1 if strpos(diag_0`i',"B20") | strpos(diag_0`i',"B21") | strpos(diag_0`i',"B22") | strpos(diag_0`i',"B24")
	}

	forvalues i = 10(1)20 {
		replace comorb_hiv = 1 if strpos(diag_`i',"B20") | strpos(diag_`i',"B21") | strpos(diag_`i',"B22") | strpos(diag_`i',"B24")
	}	
	
	egen comorb_unweightedcharlson = rowtotal(comorb_mi comorb_chf comorb_pvd comorb_cvd comorb_dem comorb_cpd comorb_rhe comorb_pud comorb_mld comorb_dmnocc comorb_dmcc comorb_hppp comorb_ren comorb_mal comorb_sld comorb_mst comorb_hiv)
	gen comorb_charlson = comorb_cvd + comorb_cpd + comorb_chf + comorb_dem + comorb_dmnocc + comorb_mld + comorb_mi + comorb_pud + comorb_pvd + comorb_rhe + (2 * comorb_dmcc) + (2 * comorb_hppp) + (2 * comorb_ren) + (2 * comorb_mal) + (3 * comorb_sld) + (6 * comorb_hiv) + (6 * comorb_mst)
	
	
	******************************************
	
	keep acsc1st encrypted_hesid mydob startage ethnos sex admidate epistart epiorder epiend epikey disdate speldur admimeth dismeth admisorc disdest provspnops procode3 gpprac diag_01 lsoa11 num_comorb comorb_unweightedcharlson comorb_charlson // dismeth = 4 means died
	merge m:1 lsoa11 using "Lookups\lsoa11_ccg17.dta", keep(1 3) nogen
	gen admi_date = date(admidate, "YMD")
	gen dis_date = date(disdate, "YMD")
	format %d admi_date dis_date
	drop admidate disdate
	gen admi_year = .
	replace admi_year = 2013 if admi_date >= date("01/04/2013", "DMY") & admi_date <= date("31/03/2014", "DMY")
	replace admi_year = 2014 if admi_date >= date("01/04/2014", "DMY") & admi_date <= date("31/03/2015", "DMY")
	replace admi_year = 2015 if admi_date >= date("01/04/2015", "DMY") & admi_date <= date("31/03/2016", "DMY")
	replace admi_year = 2016 if admi_date >= date("01/04/2016", "DMY") & admi_date <= date("31/03/2017", "DMY")
	replace admi_year = 2017 if admi_date >= date("01/04/2017", "DMY") & admi_date <= date("31/03/2018", "DMY")
	replace admi_year = 2018 if admi_date >= date("01/04/2018", "DMY") & admi_date <= date("31/03/2019", "DMY")
	tab admi_year
	
	gen admi_meth = 0
	replace admi_meth = 1 if substr(admimeth, 1, 1) == "1"
	replace admi_meth = 2 if substr(admimeth, 1, 1) == "2"
	label define admimeth_lbl 0 "Other" 1 "Elective" 2 "Emergency"
	label values admi_meth admimeth_lbl
	
	gen dis_meth = 0
	replace dis_meth = 4 if dismeth == 4
	label define dismeth_lbl 0 "Alive" 4 "In-Hospital Death"
	label values dis_meth dismeth_lbl	

	rename ethnos Eth_Code
	merge m:1 Eth_Code using "Lookups\ethnic_groups.dta", keep(1 3) nogen
	drop Eth_Descr	
	
	save "Raw_Data\bdws.dta", replace
}
***

if "`process_demographics'" == "yes" {
	*********************************
	* SEX
	*********************************

	* Check sex is constant for a particular patient
	use "Raw_Data\bdws.dta", clear
	gen index = _n
	collapse (count) index, by(encrypted_hesid sex)
	drop index
	bysort encrypted_hes: gen sexindex = _n
	tab sexindex
	/*
		   sexindex |      Freq.     Percent        Cum.
		------------+-----------------------------------
				  1 |  1,036,461      100.00      100.00
		------------+-----------------------------------
			  Total |  1,036,461      100.00
	*/

	* Yes it is a constant in our data

	***

	*********************************
	* ETHNICITY
	*********************************

	* Check ethnicity is constant for a particular patient
	use "Raw_Data\bdws.dta", clear
	gen index = _n
	collapse (count) index, by(encrypted_hesid Eth_Group)
	drop index
	bysort encrypted_hes: gen ethindex = _n
	tab ethindex
	/*
		   ethindex |      Freq.     Percent        Cum.
		------------+-----------------------------------
				  1 |  1,036,461       95.26       95.26
				  2 |     51,227        4.71       99.97
				  3 |        342        0.03      100.00
				  4 |         11        0.00      100.00
		------------+-----------------------------------
			  Total |  1,088,041      100.00
	*/

	* Ethnicity is not constant!

	* Perhaps all we will care about is %white, so re-categorise into White/Non-White/Other and see if this is more consistent
	use "Raw_Data\bdws.dta", clear
	gen index = _n
	gen new_eth_group = 1
	replace new_eth_group = . if Eth_Group == "Other or Unknown"
	replace new_eth_group = 2 if Eth_Group == "Asian" | Eth_Group == "Black" | Eth_Group == "Mixed"
	collapse (count) index, by(encrypted_hesid new_eth_group)
	drop index
	bysort encrypted_hesid: gen ethindex = _n
	tab ethindex
	/*
		   ethindex |      Freq.     Percent        Cum.
		------------+-----------------------------------
				  1 |  1,036,461       95.30       95.30
				  2 |     50,828        4.67       99.98
				  3 |        233        0.02      100.00
		------------+-----------------------------------
			  Total |  1,087,522      100.00
	*/

	* Still not consistent - lets get rid of the unknowns when there is more than one ethnicity group
	bysort encrypted_hesid: gen num_eth = _N
	drop if num_eth > 1 & new_eth_group == .
	drop num_eth ethindex

	gen index = _n
	collapse (count) index, by(encrypted_hesid new_eth_group)
	drop index
	bysort encrypted_hesid: gen ethindex = _n
	tab ethindex
	/*
		   ethindex |      Freq.     Percent        Cum.
		------------+-----------------------------------
				  1 |  1,036,461       99.85       99.85
				  2 |      1,572        0.15      100.00
		------------+-----------------------------------
			  Total |  1,038,033      100.00
	*/

	* 1,572 patients where they have both White and Non-White ethnic groups recorded - what to do about these?

	* I'm thinking to just keep the first ethnicity recorded for these people as it's only 0.1% of all patients - need to work out how to keep date ordering

	* First record the ethnic group of those with only one ethnic group
	bysort encrypted_hesid: gen num_eth = _N

	preserve
		keep if num_eth == 1
		keep encrypted_hesid new_eth_group
		tempfile single_eth
		save `single_eth'
	restore

	keep if num_eth == 2
	keep if ethindex == 1
	keep encrypted_hesid
	merge 1:m encrypted_hesid using "Raw_Data\bdws.dta", keep(1 3) nogen
	gen new_eth_group = 1
	replace new_eth_group = . if Eth_Group == "Other or Unknown"
	replace new_eth_group = 2 if Eth_Group == "Asian" | Eth_Group == "Black" | Eth_Group == "Mixed"

	sort encrypted_hesid admi_date epiorder
	collapse (firstnm) new_eth_group, by(encrypted_hesid)
	count if new_eth_group == .
	*  0
	append using `single_eth'

	replace new_eth_group = 0 if new_eth_group == .

	label define eth_label 0 "Other or Unknown" 1 "White" 2 "Non-White"
	label values new_eth_group eth_label

	sort encrypted_hesid
	save "Lookups\patient_ethnicity.dta", replace


	***

	***************************
	* AGE in 2014
	***************************

	use "Raw_Data\bdws.dta", clear

	* Check for consistent birth dates
	bysort encrypted_hesid: gen patrows = _N
	bysort encrypted_hesid mydob: gen dobrows = _N
	count if patrows ~= dobrows
	* dob is not always consistent
	preserve
		keep if patrows ~= dobrows
		count if mydob == .
		* 0
		* Keep first recorded dob if inconsistent?
		sort encrypted_hesid admi_date epiorder
		bysort encrypted_hesid: gen dobindex = _n
		keep if dobindex == 1
		gen birthyear = real(substr(string(mydob, "%15.0g"), -4, .))
		* A small number of 1800 and 1801 - no mention in data dictionary of a 'missing' value - but startage is missing in these cases - assume missing
		replace birthyear = . if birthyear < 1900
		gen age2014 = 2014 - birthyear
		gen birthmonth = trunc(mydob / 10000)
		replace age2014 = age2014 - 1 if birthmonth >= 7
		replace age2014 = 0 if age2014 < 0
		keep encrypted_hesid age2014
		tempfile mixed_dob
		save `mixed_dob'
	restore

	keep if patrows == dobrows
	bysort encrypted_hesid: gen patindex = _n
	keep if patindex == 1
	drop patindex
	gen birthyear = real(substr(string(mydob, "%15.0g"), -4, .))
	* A small number of 1800 and 1801 - no mention in data dictionary of a 'missing' value - but startage is missing in these cases - assume missing
	replace birthyear = . if birthyear < 1900
	gen age2014 = 2014 - birthyear
	gen birthmonth = trunc(mydob / 10000)
	replace age2014 = age2014 - 1 if birthmonth >= 7
	replace age2014 = 0 if age2014 < 0
	keep encrypted_hesid age2014
	append using `mixed_dob'
	sort encrypted_hesid
	save "Lookups\patient_age2014.dta", replace
}

***
if "`combine_data_demographics'" == "yes" {
	**************************
	* COMBINE DATA
	**************************
	use "Raw_Data\bdws.dta", clear
	merge m:1 encrypted_hesid using "Lookups\patient_age2014.dta", keep(1 3) nogen
	merge m:1 encrypted_hesid using "Lookups\patient_ethnicity.dta", keep(1 3) nogen
	rename admi_year Fin_Year
	* Only keep people in practices for which we have all 3 years of denominators
	merge m:1 gpprac Fin_Year using "Lookups\QOF\qof_dementia_allyears.dta", keep(3) nogen keepusing(QOF_CCG_Name similar_ccg)
	
	* Keep only the relevant CCGs
	keep if similar_ccg == 1 | strpos(QOF_CCG_Name, "NORTH SOM") | strpos(QOF_CCG_Name, "SOUTH GLOUC") | strpos(QOF_CCG_Name, "BRISTOL")
	
	*** Combine to continuous inpatient spells (CIPS) rather than episodes ***
	
	* If there's no admission date or episode start then we can't assign it to a day so drop
	drop if admi_date == . & epistart == ""  // no episodes dropped - they all have dates.
	gen epi_start = date(epistart, "YMD")
	gen epi_end = date(epiend, "YMD")
	format %d epi_start epi_end
	drop epistart epiend

	* Create transit variable to identify if people are transferring in/out/both/neither and allows for ordering same-day transfers
	* admisorc 49-53 is NHS other hospital provider
	* admimeth 2B is transfer from another hospital in an emergency
	* admimeth 81 is transfer from another hospital not in an emergency
	* disdest 49-53 is NHS other hospital provider

	* Set transit = 0 if this is an episode of stay with no transfers in or out
	gen transit = 0
	* Set transit = 1 if this is a transfer to another hospital
	replace transit = 1 if ((admisorc < 49 | admisorc > 53) & admimeth != "81" & admimeth != "2B") & (disdest >= 49 & disdest <= 53)
	* Set transit = 3 if this is a transfer from another hospital
	replace transit = 3 if ((admisorc >= 49 & admisorc <= 53) | admimeth == "81" | admimeth == "2B") & (disdest < 49 | disdest > 53)
	* Set transit = 2 if this is a transfer in from and a transfer out to another hospital
	replace transit = 2 if ((admisorc >= 49 & admisorc <= 53) | admimeth == "81" | admimeth == "2B") & (disdest >= 49 & disdest <= 53)
	tab transit
	/*
		transit |      Freq.     Percent        Cum.
		--------+-----------------------------------
		      0 |    296,826       91.96       91.96
			  1 |      2,751        0.85       92.81
			  2 |        680        0.21       93.02
			  3 |     22,530        6.98      100.00
		--------+-----------------------------------
		  Total |    322,787      100.00
	*/

	* Check for duplicated episodes
	gsort encrypted_hesid epi_start epiorder epi_end transit admi_date dis_date epikey
	by encrypted_hesid epi_start epiorder epi_end transit: gen index = _n
	drop if index > 1  // 63 out of 322,787 dropped
	drop index

	* Group in admissions/spells
	gsort encrypted_hesid epi_start epi_end epiorder transit epikey
	gen spell = _n
	replace spell = spell[_n-1] if encrypted_hesid == encrypted_hesid[_n-1] & provspnops == provspnops[_n-1] & procode3 == procode3[_n-1] & admi_date == admi_date[_n-1]
	egen NHSDspell = group(spell)

	* collapse into spells and keep the most relevant information
	collapse (firstnm) encrypted_hesid admi_date sex Fin_Year age2014 new_eth_group diag_01 acsc1st lsoa11 QOF_CCG_Name similar_ccg admi_meth (lastnm) speldur dis_meth dis_date (max) num_comorb comorb_unweightedcharlson comorb_charlson, by(NHSDspell)
	replace speldur = dis_date - admi_date if speldur == .
	
	gen area = 0
	replace area = 1 if strpos(QOF_CCG_Name, "NORTH SOM") | strpos(QOF_CCG_Name, "SOUTH GLOUC")
	replace area = 2 if similar_ccg == 1
	label define area_lbl 0 "Bristol" 1 "NSSG" 2 "Similar CCGs"
	label values area area_lbl
	
	* Check the dementia diagnoses in primary diagnosis position
	gen F00_Alz = 0
	replace F00_Alz = 1 if strpos(diag_01, "F00")
	gen F01_Vasc = 0
	replace F01_Vasc = 1 if strpos(diag_01, "F01")
	gen F02_Other = 0
	replace F02_Other = 1 if strpos(diag_01, "F02")
	gen F03_Unspec = 0
	replace F03_Unspec = 1 if strpos(diag_01, "F03")
	gen F051_Del = 0
	replace F051_Del = 1 if strpos(diag_01, "F051")
	gen G30_Alz = 0
	replace G30_Alz = 1 if strpos(diag_01, "G30")
	gen G31_Other = 0
	replace G31_Other = 1 if strpos(diag_01, "G31")

	egen num_dem_diag = rowtotal(F00_Alz F01_Vasc F02_Other F03_Unspec F051_Del G30_Alz G31_Other)
	gen primary_dem = cond(num_dem_diag > 0, 1, 0)
	gen primary_acsc = cond(acsc1st ~=., 1, 0)
	
	keep acsc1st diag_01 lsoa11 QOF_CCG_Name similar_ccg admi_meth dis_date dis_meth num_comorb comorb_unweightedcharlson comorb_charlson encrypted_hesid admi_date sex Fin_Year age2014 new_eth_group area primary_dem primary_acsc
	
	save "Raw_Data\Combined_Data.dta", replace
}
***

if "`demographics_by_ccg_2014'" == "yes" {
	**************************
	* DEMOGRAPHICS - 2014
	**************************

	*** PERCENT WOMEN ***

	* Percentage of women of people admitted to hospital for dementia for the 10 'similar' CCGs combined
	use "Raw_Data\Combined_Data.dta", clear
	*keep if Fin_Year == 2014

	bysort encrypted_hesid: gen patindex = _n
	keep if patindex == 1
	drop patindex

	* Only a very small number of non-male/female so exclude these
	keep if sex == 1 | sex == 2  // (15 observations deleted)

	collapse (count) freq=age2014, by(sex area)
	rename area index
	reshape wide freq, i(index) j(sex)
	rename freq1 men
	rename freq2 women
	gen total = men + women
	gen pct_women = (women / total) * 100
	
	save "Demographics\percent_women", replace

	***

	*** PERCENT WHITE ETHNICITY ***

	* Percent white ethnicity admitted to hospital for dementia for the 10 'similar' CCGs combined
	use "Raw_Data\Combined_Data.dta", clear
	*keep if Fin_Year == 2014

	bysort encrypted_hesid: gen patindex = _n
	keep if patindex == 1
	drop patindex

	collapse (count) freq=age2014, by(new_eth_group area)
	rename area index
	reshape wide freq, i(index) j(new_eth_group)
	* There are a reasonable number of unknowns, but for now I am going to assume this is unbiased missingness and look at percent of known ethnicity
	rename freq0 unknown
	rename freq1 white
	rename freq2 non_white
	replace non_white = 0 if non_white == .
	gen total = white + non_white
	gen pct_white = (white / total) * 100

	save "Demographics\percent_white", replace

	***

	*** AGE PROFILE ***

	* Age profile (in 2014) for the 10 similar CCGs combined
	use "Raw_Data\Combined_Data.dta", clear
	*keep if Fin_Year == 2014

	bysort encrypted_hesid: gen patindex = _n
	keep if patindex == 1
	drop patindex

	egen age2014_grp = cut(age2014), at(0, 65, 75, 85, 200)

	* 6 are missing - drop these as should make minimal difference
	drop if age2014_grp == .

	collapse (count) freq=age2014, by(age2014_grp area)
	rename area index
	reshape wide freq, i(index) j(age2014_grp)
	egen total = rowtotal(freq0 freq65 freq75 freq85)
	gen pct_75plus = ((freq75 + freq85) / total) * 100
	gen pct_85plus = (freq85 / total) * 100

	save "Demographics\age_profile", replace
}
***

if "`rates_in_2014'" == "yes" {
	*******************************************************
	*** ADMISSION AND DEATH RATES AND LENGTH OF STAY
	*******************************************************

	* Admission and death rates in 2014 for the 10 similar CCGs combined
	use "Raw_Data\Combined_Data.dta", clear
	keep if Fin_Year == 2014

	gen speldur = .
	replace speldur = dis_date - admi_date if dis_date ~= . & dis_date > date("1900-01-01", "YMD")  // left with 0.6% missing speldur - not too bad!
	gen inhosp_death = cond(dis_meth == 4, 1, 0)
	merge m:1 QOF_CCG_Name Fin_Year using "Lookups\QOF\ccg_dementia_allyears.dta", keep(1 3) nogen

	bysort QOF_CCG_Name: gen ccgindex = _n
	replace pop = 0 if ccgindex > 1
	replace dementia = 0 if ccgindex > 1
	gen speldur30 = cond(speldur > 30, 1, 0)
	gen speldur90 = cond(speldur > 90, 1, 0)
	collapse (count) freq=age2014 (median) median_speldur=speldur (p25) p25_speldur=speldur (p75) p75_speldur=speldur (sum) inhosp_death pop dementia speldur30 speldur90, by(area)

	gen adm_rate = freq / dementia
	gen death_rate = inhosp_death / dementia
	gen prop_30 = speldur30 / freq
	gen prop_90 = speldur90 / freq
	rename area index
	gen Fin_Year = 2014
	save "Demographics\admission_rate", replace
}
***

if "`combine_demographics_2014'" == "yes" {
	* Combine the demographics
	use "Demographics\percent_women", clear
	keep index pct_women
	merge 1:1 index using "Demographics\percent_white", keep(1 3) keepusing(pct_white) nogen
	merge 1:1 index using "Demographics\age_profile", keep(1 3) keepusing(pct_75plus pct_85plus) nogen
	merge 1:1 index using "Demographics\admission_rate", keep(1 3) keepusing(adm_rate median_speldur p25_speldur p75_speldur prop_30 prop_90 death_rate) nogen
}
***

if "`monthly_data'" == "yes" {
	************************
	*** MONTHLY DATA ***
	************************

	*** 10 Similar CCGs ***
	use "Raw_Data\Combined_Data.dta", clear

	gen speldur = .
	replace speldur = dis_date - admi_date if dis_date ~= . & dis_date > date("1900-01-01", "YMD") & dis_date >= admi_date  // left with 0.6% missing speldur - not too bad!
	gen inhosp_death = cond(dis_meth == 4, 1, 0)
	gen admi_month = month(admi_date)
	gen admi_year = year(admi_date)
	merge m:1 QOF_CCG_Name Fin_Year using "Lookups\QOF\ccg_dementia_allyears.dta", keep(1 3) nogen
	bysort QOF_CCG_Name admi_month admi_year: gen blockindex = _n
	replace pop = 0 if blockindex > 1
	replace dementia = 0 if blockindex > 1
	gen speldur30 = cond(speldur > 30 & speldur ~= ., 1, 0)
	gen speldur90 = cond(speldur > 90 & speldur ~= ., 1, 0)
	gen censored_speldur = .
	replace censored_speldur = speldur if speldur <= 30
	collapse (count) freq=age2014 (median) median_speldur=speldur (p25) p25_speldur=speldur (p75) p75_spel_dur=speldur (sum) inhosp_death pop dementia speldur30 speldur90 (mean) censored_speldur comorbs=num_comorb unweightedcharlson=comorb_unweightedcharlson charlson=comorb_charlson, by(admi_month admi_year area)

	* Per 100 dementia patients
	gen adm_rate = freq / (dementia / 100)
	gen death_rate = inhosp_death / (freq / 100)
	gen prop_30 = speldur30 / freq
	gen prop_90 = speldur90 / freq
	gen index = "Similar CCGs"
	replace index = "NSSG" if area == 1
	replace index = "Bristol" if area == 0

	save "Raw_Data\monthly_data.dta", replace
	export delimited using "Raw_Data\monthly_data.txt", delimiter(tab) replace
}
**************************************************

if "`monthly_acsc_data'" == "yes" {
	************************
	*** MONTHLY ACSC DATA ***
	************************
	use "Raw_Data\Combined_Data.dta", clear
	keep if primary_acsc == 1 // has to be primary_acsc
	keep if admi_meth == 2 // has to be emergency admission to be potentially avoidable
	
	gen speldur = .
	replace speldur = dis_date - admi_date if dis_date ~= . & dis_date > date("1900-01-01", "YMD") & dis_date >= admi_date
	gen inhosp_death = cond(dis_meth == 4, 1, 0)
	gen admi_month = month(admi_date)
	gen admi_year = year(admi_date)
	merge m:1 QOF_CCG_Name Fin_Year using "Lookups\QOF\ccg_dementia_allyears.dta", keep(1 3) nogen
	bysort QOF_CCG_Name admi_month admi_year: gen blockindex = _n
	replace pop = 0 if blockindex > 1
	replace dementia = 0 if blockindex > 1
	gen speldur30 = cond(speldur > 30 & speldur ~= ., 1, 0)
	gen speldur90 = cond(speldur > 90 & speldur ~= ., 1, 0)
	gen censored_speldur = .
	replace censored_speldur = speldur if speldur <= 30
	collapse (count) freq=age2014 (median) median_speldur=speldur (p25) p25_speldur=speldur (p75) p75_spel_dur=speldur (sum) inhosp_death pop dementia speldur30 speldur90 (mean) censored_speldur comorbs=num_comorb unweightedcharlson=comorb_unweightedcharlson charlson=comorb_charlson, by(admi_month admi_year area)

	* Per 100 dementia patients
	gen adm_rate = freq / (dementia / 100)
	gen death_rate = inhosp_death / (freq / 100)
	gen prop_30 = speldur30 / freq
	gen prop_90 = speldur90 / freq
	gen index = "Similar CCGs"
	replace index = "NSSG" if area == 1
	replace index = "Bristol" if area == 0

	save "Raw_Data\monthly_acsc_data.dta", replace
	export delimited using "Raw_Data\monthly_acsc_data.txt", delimiter(tab) replace
}
**************************************************

*** Do some analysis ***
if "`analyse_acsc'" == "yes" {
	use "Raw_Data\monthly_acsc_data.dta", clear
	drop if index == "NSSG"
	
	* Change the time period for 2 years before and 3 after
	drop if admi_year == 2013 & admi_month < 10
	drop if admi_year == 2019
	drop if admi_year == 2018 & admi_month >= 10
	
	sort index admi_year admi_month
	by index: egen timepoint = seq(), from(0)
	
	gen index_num = 0
	replace index_num = 1 if index == "Bristol"
	
	gen levelchange = 0
	replace levelchange = 1 if timepoint >= 24
	
	gen trendchange = 0
	replace trendchange = timepoint - 24 if timepoint >= 24
	
	gen bristol_time = 0
	replace bristol_time = index_num * timepoint
	gen bristol_levelchange = 0
	replace bristol_levelchange = index_num * levelchange
	gen bristol_trendchange = 0
	replace bristol_trendchange = index_num * trendchange
	
	* Create seasons
	gen season = 0
	replace season = 1 if inlist(admi_month, 3, 4, 5)
	replace season = 2 if inlist(admi_month, 6, 7, 8)
	replace season = 3 if inlist(admi_month, 9, 10, 11)

	* Dummy variables just for summer and winter
	gen summer = cond(season == 2, 1, 0)
	gen winter = cond(season == 0, 1, 0)	
	
	save "its_acsc_analysis_data", replace

	/*
	**** TESTING OUT POSSIBLE ANALYSIS METHODS ****
	
	poisson freq timepoint levelchange trendchange index_num bristol_time bristol_levelchange bristol_trendchange, exposure(dementia) irr  // Doesn't account for auto-correlation
	tsset index_num timepoint
	glm freq timepoint levelchange trendchange index_num bristol_time bristol_levelchange bristol_trendchange, family(poisson) link(log) vce(hac nwest) exposure(dementia) eform // Get error about repeated time values, can do the intervention vs control one-at-a-time
	newey adm_rate timepoint levelchange trendchange index_num bristol_time bristol_levelchange bristol_trendchange, lag(5) force // Runs fine, not a poisson model so assume normal linear regression
	
	xtset index_num timepoint
	xtpoisson freq timepoint levelchange trendchange index_num bristol_time bristol_levelchange bristol_trendchange, pa exposure(dementia) corr(ar1) irr  // allows us to do intervention versus control as population-average poisson regression but makes us specify an AR function for the autocorrelation which at the moment I am assuming to be AR(1) - could do sensitivity with more? And do model comparisons with the deviance stored in `e(deviance)'
	xtpoisson freq timepoint levelchange trendchange index_num bristol_time bristol_levelchange bristol_trendchange, pa exposure(dementia) corr(unstructured) iterate(200) irr // try with unstructured correlation to allow all sorts of relationships - doesn't converge (although it does stop so not sure why it stops if it reports not converging and hasn't reached maximum iterations?)
	*/

	local lags 2
	
	postfile model_results str30 modelname bristol_rr bristol_lci bristol_uci bristol_p pretrenddiff_rr pretrenddiff_lci pretrenddiff_uci pretrenddiff_p leveldiff_rr leveldiff_lci leveldiff_uci leveldiff_p trenddiff_rr trenddiff_lci trenddiff_uci trenddiff_p using "model_results.dta", replace
	
	*** Admission rates ***
	use "its_acsc_analysis_data", clear
	
	xtset index_num timepoint
	xtpoisson freq timepoint levelchange trendchange index_num bristol_time bristol_levelchange bristol_trendchange i.season, pa exposure(dementia) corr(ar`lags') irr 
	gen season_avg = (_b[1.season] + _b[2.season] + _b[3.season]) / 4  // Need to divide by 4 to include the impact of winter at 0 (it's the baseline season)
	gen adm_prediction = (exp(_b[_cons] + (_b[timepoint] * timepoint) + (_b[levelchange] * levelchange) + (_b[trendchange] * trendchange) + (_b[index_num] * index_num) + (_b[bristol_time] * bristol_time) + (_b[bristol_levelchange] * bristol_levelchange) + (_b[bristol_trendchange] * bristol_trendchange) + season_avg + log(dementia)) / dementia) * 100
	
	local bristol_rr = el(r(table), 1, colnumb(r(table), "index_num"))
	local bristol_lci = el(r(table), 5, colnumb(r(table), "index_num"))
	local bristol_uci = el(r(table), 6, colnumb(r(table), "index_num"))
	local bristol_p = el(r(table), 4, colnumb(r(table), "index_num"))
	local pretrend_rr = el(r(table), 1, colnumb(r(table), "bristol_time"))
	local pretrend_lci = el(r(table), 5, colnumb(r(table), "bristol_time"))
	local pretrend_uci = el(r(table), 6, colnumb(r(table), "bristol_time"))
	local pretrend_p = el(r(table), 4, colnumb(r(table), "bristol_time"))
	local levelchange_rr = el(r(table), 1, colnumb(r(table), "bristol_levelchange"))
	local levelchange_lci = el(r(table), 5, colnumb(r(table), "bristol_levelchange"))
	local levelchange_uci = el(r(table), 6, colnumb(r(table), "bristol_levelchange"))
	local levelchange_p = el(r(table), 4, colnumb(r(table), "bristol_levelchange"))
	local slopechange_rr = el(r(table), 1, colnumb(r(table), "bristol_trendchange"))
	local slopechange_lci = el(r(table), 5, colnumb(r(table), "bristol_trendchange"))
	local slopechange_uci = el(r(table), 6, colnumb(r(table), "bristol_trendchange"))
	local slopechange_p = el(r(table), 4, colnumb(r(table), "bristol_trendchange"))
	post model_results ("Admissions") (`bristol_rr') (`bristol_lci') (`bristol_uci') (`bristol_p') (`pretrend_rr') (`pretrend_lci') (`pretrend_uci') (`pretrend_p') (`levelchange_rr') (`levelchange_lci') (`levelchange_uci') (`levelchange_p') (`slopechange_rr') (`slopechange_lci') (`slopechange_uci') (`slopechange_p')	
	
	keep admi_year admi_month index adm_rate adm_prediction
	order admi_year admi_month index adm_rate adm_prediction
	
	save "Graphs\Admissions_Graph_Data.dta", replace
	
	
	*** In-hospital mortality ***
	use "its_acsc_analysis_data", clear
	
	xtset index_num timepoint
	xtpoisson inhosp_death timepoint levelchange trendchange index_num bristol_time bristol_levelchange bristol_trendchange i.season, pa exposure(freq) corr(ar`lags') irr 
	gen season_avg = (_b[1.season] + _b[2.season] + _b[3.season]) / 4
	gen death_prediction = (exp(_b[_cons] + (_b[timepoint] * timepoint) + (_b[levelchange] * levelchange) + (_b[trendchange] * trendchange) + (_b[index_num] * index_num) + (_b[bristol_time] * bristol_time) + (_b[bristol_levelchange] * bristol_levelchange) + (_b[bristol_trendchange] * bristol_trendchange) + season_avg + log(freq)) / freq) * 100
	
	local bristol_rr = el(r(table), 1, colnumb(r(table), "index_num"))
	local bristol_lci = el(r(table), 5, colnumb(r(table), "index_num"))
	local bristol_uci = el(r(table), 6, colnumb(r(table), "index_num"))
	local bristol_p = el(r(table), 4, colnumb(r(table), "index_num"))
	local pretrend_rr = el(r(table), 1, colnumb(r(table), "bristol_time"))
	local pretrend_lci = el(r(table), 5, colnumb(r(table), "bristol_time"))
	local pretrend_uci = el(r(table), 6, colnumb(r(table), "bristol_time"))
	local pretrend_p = el(r(table), 4, colnumb(r(table), "bristol_time"))
	local levelchange_rr = el(r(table), 1, colnumb(r(table), "bristol_levelchange"))
	local levelchange_lci = el(r(table), 5, colnumb(r(table), "bristol_levelchange"))
	local levelchange_uci = el(r(table), 6, colnumb(r(table), "bristol_levelchange"))
	local levelchange_p = el(r(table), 4, colnumb(r(table), "bristol_levelchange"))
	local slopechange_rr = el(r(table), 1, colnumb(r(table), "bristol_trendchange"))
	local slopechange_lci = el(r(table), 5, colnumb(r(table), "bristol_trendchange"))
	local slopechange_uci = el(r(table), 6, colnumb(r(table), "bristol_trendchange"))
	local slopechange_p = el(r(table), 4, colnumb(r(table), "bristol_trendchange"))
	post model_results ("In-hospital Deaths") (`bristol_rr') (`bristol_lci') (`bristol_uci') (`bristol_p') (`pretrend_rr') (`pretrend_lci') (`pretrend_uci') (`pretrend_p') (`levelchange_rr') (`levelchange_lci') (`levelchange_uci') (`levelchange_p') (`slopechange_rr') (`slopechange_lci') (`slopechange_uci') (`slopechange_p')	
	
	keep admi_year admi_month index death_rate death_prediction
	order admi_year admi_month index death_rate death_prediction
	
	save "Graphs\Deaths_Graph_Data.dta", replace	
	
	
	*** Spell Duration > 30 ***
	use "its_acsc_analysis_data", clear
	
	xtset index_num timepoint
	xtpoisson speldur30 timepoint levelchange trendchange index_num bristol_time bristol_levelchange bristol_trendchange i.season, pa exposure(freq) corr(ar`lags') irr 
	gen season_avg = (_b[1.season] + _b[2.season] + _b[3.season]) / 4
	gen speldur30_prediction = (exp(_b[_cons] + (_b[timepoint] * timepoint) + (_b[levelchange] * levelchange) + (_b[trendchange] * trendchange) + (_b[index_num] * index_num) + (_b[bristol_time] * bristol_time) + (_b[bristol_levelchange] * bristol_levelchange) + (_b[bristol_trendchange] * bristol_trendchange) + season_avg + log(freq)) / freq)
	
	local bristol_rr = el(r(table), 1, colnumb(r(table), "index_num"))
	local bristol_lci = el(r(table), 5, colnumb(r(table), "index_num"))
	local bristol_uci = el(r(table), 6, colnumb(r(table), "index_num"))
	local bristol_p = el(r(table), 4, colnumb(r(table), "index_num"))
	local pretrend_rr = el(r(table), 1, colnumb(r(table), "bristol_time"))
	local pretrend_lci = el(r(table), 5, colnumb(r(table), "bristol_time"))
	local pretrend_uci = el(r(table), 6, colnumb(r(table), "bristol_time"))
	local pretrend_p = el(r(table), 4, colnumb(r(table), "bristol_time"))
	local levelchange_rr = el(r(table), 1, colnumb(r(table), "bristol_levelchange"))
	local levelchange_lci = el(r(table), 5, colnumb(r(table), "bristol_levelchange"))
	local levelchange_uci = el(r(table), 6, colnumb(r(table), "bristol_levelchange"))
	local levelchange_p = el(r(table), 4, colnumb(r(table), "bristol_levelchange"))
	local slopechange_rr = el(r(table), 1, colnumb(r(table), "bristol_trendchange"))
	local slopechange_lci = el(r(table), 5, colnumb(r(table), "bristol_trendchange"))
	local slopechange_uci = el(r(table), 6, colnumb(r(table), "bristol_trendchange"))
	local slopechange_p = el(r(table), 4, colnumb(r(table), "bristol_trendchange"))
	post model_results ("Spell > 30") (`bristol_rr') (`bristol_lci') (`bristol_uci') (`bristol_p') (`pretrend_rr') (`pretrend_lci') (`pretrend_uci') (`pretrend_p') (`levelchange_rr') (`levelchange_lci') (`levelchange_uci') (`levelchange_p') (`slopechange_rr') (`slopechange_lci') (`slopechange_uci') (`slopechange_p')	
	
	keep admi_year admi_month index prop_30 speldur30_prediction
	order admi_year admi_month index prop_30 speldur30_prediction
	
	save "Graphs\SpelDur30_Graph_Data.dta", replace	
	
	
	*** Average spell duration when <= 30 days
	use "its_acsc_analysis_data", clear
	
	tsset index_num timepoint
	newey censored_speldur timepoint levelchange trendchange index_num bristol_time bristol_levelchange bristol_trendchange i.season, lag(`lags') force
	gen season_avg = (_b[1.season] + _b[2.season] + _b[3.season]) / 4
	gen censored_speldur_prediction = _b[_cons] + (_b[timepoint] * timepoint) + (_b[levelchange] * levelchange) + (_b[trendchange] * trendchange) + (_b[index_num] * index_num) + (_b[bristol_time] * bristol_time) + (_b[bristol_levelchange] * bristol_levelchange) + (_b[bristol_trendchange] * bristol_trendchange) + season_avg
	
	local bristol_rr = el(r(table), 1, colnumb(r(table), "index_num"))
	local bristol_lci = el(r(table), 5, colnumb(r(table), "index_num"))
	local bristol_uci = el(r(table), 6, colnumb(r(table), "index_num"))
	local bristol_p = el(r(table), 4, colnumb(r(table), "index_num"))
	local pretrend_rr = el(r(table), 1, colnumb(r(table), "bristol_time"))
	local pretrend_lci = el(r(table), 5, colnumb(r(table), "bristol_time"))
	local pretrend_uci = el(r(table), 6, colnumb(r(table), "bristol_time"))
	local pretrend_p = el(r(table), 4, colnumb(r(table), "bristol_time"))
	local levelchange_rr = el(r(table), 1, colnumb(r(table), "bristol_levelchange"))
	local levelchange_lci = el(r(table), 5, colnumb(r(table), "bristol_levelchange"))
	local levelchange_uci = el(r(table), 6, colnumb(r(table), "bristol_levelchange"))
	local levelchange_p = el(r(table), 4, colnumb(r(table), "bristol_levelchange"))
	local slopechange_rr = el(r(table), 1, colnumb(r(table), "bristol_trendchange"))
	local slopechange_lci = el(r(table), 5, colnumb(r(table), "bristol_trendchange"))
	local slopechange_uci = el(r(table), 6, colnumb(r(table), "bristol_trendchange"))
	local slopechange_p = el(r(table), 4, colnumb(r(table), "bristol_trendchange"))
	post model_results ("Average Spell") (`bristol_rr') (`bristol_lci') (`bristol_uci') (`bristol_p') (`pretrend_rr') (`pretrend_lci') (`pretrend_uci') (`pretrend_p') (`levelchange_rr') (`levelchange_lci') (`levelchange_uci') (`levelchange_p') (`slopechange_rr') (`slopechange_lci') (`slopechange_uci') (`slopechange_p')	
	
	keep admi_year admi_month index censored_speldur censored_speldur_prediction
	order admi_year admi_month index censored_speldur censored_speldur_prediction
	
	save "Graphs\AvgSpell_Graph_Data.dta", replace
	
	
	*** Average comorbidities ***
	use "its_acsc_analysis_data", clear
	
	tsset index_num timepoint
	newey unweightedcharlson timepoint levelchange trendchange index_num bristol_time bristol_levelchange bristol_trendchange i.season, lag(`lags') force
	gen season_avg = (_b[1.season] + _b[2.season] + _b[3.season]) / 4
	gen charslon_prediction = _b[_cons] + (_b[timepoint] * timepoint) + (_b[levelchange] * levelchange) + (_b[trendchange] * trendchange) + (_b[index_num] * index_num) + (_b[bristol_time] * bristol_time) + (_b[bristol_levelchange] * bristol_levelchange) + (_b[bristol_trendchange] * bristol_trendchange) + season_avg
	
	local bristol_rr = el(r(table), 1, colnumb(r(table), "index_num"))
	local bristol_lci = el(r(table), 5, colnumb(r(table), "index_num"))
	local bristol_uci = el(r(table), 6, colnumb(r(table), "index_num"))
	local bristol_p = el(r(table), 4, colnumb(r(table), "index_num"))
	local pretrend_rr = el(r(table), 1, colnumb(r(table), "bristol_time"))
	local pretrend_lci = el(r(table), 5, colnumb(r(table), "bristol_time"))
	local pretrend_uci = el(r(table), 6, colnumb(r(table), "bristol_time"))
	local pretrend_p = el(r(table), 4, colnumb(r(table), "bristol_time"))
	local levelchange_rr = el(r(table), 1, colnumb(r(table), "bristol_levelchange"))
	local levelchange_lci = el(r(table), 5, colnumb(r(table), "bristol_levelchange"))
	local levelchange_uci = el(r(table), 6, colnumb(r(table), "bristol_levelchange"))
	local levelchange_p = el(r(table), 4, colnumb(r(table), "bristol_levelchange"))
	local slopechange_rr = el(r(table), 1, colnumb(r(table), "bristol_trendchange"))
	local slopechange_lci = el(r(table), 5, colnumb(r(table), "bristol_trendchange"))
	local slopechange_uci = el(r(table), 6, colnumb(r(table), "bristol_trendchange"))
	local slopechange_p = el(r(table), 4, colnumb(r(table), "bristol_trendchange"))
	post model_results ("Average Comorbidities") (`bristol_rr') (`bristol_lci') (`bristol_uci') (`bristol_p') (`pretrend_rr') (`pretrend_lci') (`pretrend_uci') (`pretrend_p') (`levelchange_rr') (`levelchange_lci') (`levelchange_uci') (`levelchange_p') (`slopechange_rr') (`slopechange_lci') (`slopechange_uci') (`slopechange_p')	
	
	keep admi_year admi_month index unweightedcharlson charslon_prediction
	order admi_year admi_month index unweightedcharlson charslon_prediction
	
	save "Graphs\Charlson_Graph_Data.dta", replace
	
	
	postclose model_results
}
