#pragma rtGlobals=3		// Use modern global access method and strict wave access.
#include ":ForceRamp",version>=2
#include ":SearchForMolecules"
#include ":ProteinDaemon"

Menu "Force Ramp Fishing"
	"Initialize FR Fishing", InitializeForceRampFishing()
	"Start FR Fishing", DoFRFishing()
	"Stop FR Fishing",StopFRFishing()
	"Show FR Fishing Panel",DisplayFRFPanel("ForceRampFishingPanel")	
	"Show Ramp Panel",DisplayFRFPanel("FRF_RampPanel")	
End

Function InitializeForceRampFishing()
	
	NewDataFolder/O root:FRFishing
	NewDataFolder/O root:FRFishing:SavedData
	SetDataFolder root:FRFishing
	MakeFRFSettingsWave()
	MakeFRFWaveNamesCallback()
	MakeSimpleFishDetectionWave()
	
	MakeForceRampWave(OutputWaveName="root:FRFishing:RampSettings")
	MakeFRWaveNamesCallback(OutputWaveName="root:FRFishing:RampStrSettings")
	
	// Initialize ramp settings for force ramp on a protein
	Wave RampSettings=root:FRFishing:RampSettings
	Wave/T RampStrSettings=root:FRFishing:RampStrSettings
	RampSettings[%$"Surface Trigger"]=75e-12
	RampSettings[%$"Molecule Trigger"]=15e-12
	RampSettings[%$"Approach Velocity"]=500e-9
	RampSettings[%$"Retract Velocity"]=50e-9
	RampSettings[%$"Surface Dwell Time"]=2
	RampSettings[%$"No Trigger Distance"]=30e-9
	RampSettings[%$"Extension Distance"]=250e-9
	RampSettings[%$"Sampling Rate"]=50000
	RampSettings[%'Engage Second Trigger']=0
	RampSettings[%'UseTriggerFilter']=0

	RampStrSettings[%Deflection]="root:FRFishing:DefV_Ramp"
	RampStrSettings[%ZSensor]="root:FRFishing:ZSensor_Ramp"
	RampStrSettings[%$"CTFC Settings"]="root:FRFishing:TriggerInfo"
	RampStrSettings[%Callback]="FRFishingCallback()"
	
	// Show the clamp and ramp panels
	DisplayFRFPanel("ForceRampFishingPanel")	
	DisplayFRFPanel("FRF_RampPanel")	


End

Function DoFRFishing()
	Wave FRFSettings=root:FRFishing:FRFSettings
	
	IF(!FRFSettings[%StopFRF])
		DetermineFRFOffset()
	Else
		print "End FR Fishing Program"
	EndIf
End

Function DetermineFRFOffset()
	Make/O/N=100 root:FRFishing:DeflectionOffsetData
	Wave DeflectionOffsetData=root:FRFishing:DeflectionOffsetData
	Variable Error=0
	String CallbackStr="DetermineFRFOffsetCallback()"
	Error+= td_xSetInWave(0, "0,0", "Deflection", DeflectionOffsetData, CallbackStr,100)

	// Execute read for offset
	Error +=td_WriteString("Event.0", "once")

	if (Error>0)
		print "Error in DetermineFRFOffset: ", Error
	endif
End

Function DetermineFRFOffsetCallback()
	Wave DeflectionOffsetData=root:FRFishing:DeflectionOffsetData
	WaveStats/Q DeflectionOffsetData
	Variable DeflectionOffset=V_avg
	Wave FRFSettings=root:FRFishing:FRFSettings
	FRFSettings[%DefVOffset]=DeflectionOffset

	Wave RampSettings=root:FRFishing:RampSettings
	Wave/T RampStrSettings=root:FRFishing:RampStrSettings
	RampSettings[%DefVOffset]=DeflectionOffset
	If(RampSettings[%UseTriggerFilter])
		DoForceRampFiltered(RampSettings,RampStrSettings,RampSettings[%TriggerFilterFreq])
	Else
		DoForceRamp(RampSettings,RampStrSettings)			
	EndIf
End

Function StopFRFishing()
	Wave FRFSettings=root:FRFishing:FRFSettings
	FRFSettings[%StopFRF]=1
End


Function FRFishingCallback()
	Wave/T TriggerInfo=root:FRFishing:TriggerInfo
	Wave FRFSettings=root:FRFishing:FRFSettings
	Wave/T FRFWaveNamesCallback=root:FRFishing:FRFWaveNamesCallback
	Wave DefVolts=root:FRFishing:DefV_Ramp
	Wave ZSensorVolts = root:FRFishing:ZSensor_Ramp
	Wave RampSettings=root:FRFishing:RampSettings
	Wave/T RampStrSettings=root:FRFishing:RampStrSettings

	variable Error = 0
	
	// Save initial force ramp with suffix _IFR (stands for initial force ramp)
	String SaveName=FRFWaveNamesCallback[%SaveName]
	SaveAsAsylumForceRamp(SaveName,FRFSettings[%Iteration],DefVolts,ZSensorVolts)
	
	// Check to see if molecule is attached.  If Triggertime2 is greater than 400,000, then molecule did NOT attach
	Variable MoleculeAttached=0
	If(RampSettings[%'Engage Second Trigger'])
		MoleculeAttached=1
		Error+=td_ReadGroup("ARC.CTFC",TriggerInfo)
		if (str2num(TriggerInfo[%TriggerTime2])> 400000)
			MoleculeAttached=0
		endif
	
		If (Error>0)
			Print "Error in FRFCallback() : " + num2str(Error)
		EndIf
	Else
		MoleculeAttached=DidWeCatchAFish()
	EndIf // Did we get a molecule trigger
	
	If(MoleculeAttached)
		SetVariable CatchAFishSV,value= _STR:"Yes",win=ForceRampFishingPanel
		// Print "Caught a fish on iteration: " +num2str(FRFSettings[%Iteration])
	Else
		SetVariable CatchAFishSV,value= _STR:"No",win=ForceRampFishingPanel
	EndIf

	Variable ExecuteCallbacks=(!MoleculeAttached)||(MoleculeAttached&&!FRFSettings[%DoCatchFishAction])

	FRFSettings[%Iteration]+=1
	If(!FRFSettings[%StopFRF]&&ExecuteCallbacks)
		If(FRFSettings[%UseSearchGrid]&&!FRFSettings[%UseZeroThePD])
			SearchForMolecule(FoundMolecule=MoleculeAttached,Callback="DoFRFishing()")
		EndIf
		If(FRFSettings[%UseSearchGrid]&&FRFSettings[%UseZeroThePD])
			Wave/T ZeroThePDCallbackWave=root:ZeroThePD:ZeroThePDCallbackWave
			ZeroThePDCallbackWave[%Callback]="DoFRFishing()"
			SearchForMolecule(FoundMolecule=MoleculeAttached,Callback="DoZeroPD()")
		EndIf
		If(!FRFSettings[%UseSearchGrid]&&FRFSettings[%UseZeroThePD])
			Wave/T ZeroThePDCallbackWave=root:ZeroThePD:ZeroThePDCallbackWave
			ZeroThePDCallbackWave[%Callback]="DoFRFishing()"
			DoZeroPD()
		EndIf
		If(!FRFSettings[%UseSearchGrid]&&!FRFSettings[%UseZeroThePD])
			DoFRFishing()
		EndIf
	EndIf

	If(!FRFSettings[%StopFRF]&&MoleculeAttached&&FRFSettings[%DoCatchFishAction])
		Execute FRFWaveNamesCallback[%Callback]
	EndIf
	
	If(FRFSettings[%StopFRF])
		Print "End Fishing Program on iteration: " +num2str(FRFSettings[%Iteration]-1)
	EndIf
	
	
	
End

// Starting force and extension thresholds. Might make it fancier if necessary
Function DidWeCatchAFish()
	Wave DefVolts=root:FRFishing:DefV_Ramp
	Wave ZSensorVolts = root:FRFishing:ZSensor_Ramp
	Wave FRFSettings=root:FRFishing:FRFSettings
	Wave FishDetectionSettings=root:FRFishing:FishDetectionSettings
	Wave/T TriggerInfo=root:FRFishing:TriggerInfo

	FishDetectionSettings[%DefVOffset]=FRFSettings[%DefVOffset]
	
	Variable StartRetractTime=str2num(TriggerInfo[%TriggerTime1])+str2num(TriggerInfo[%DwellTime1])
	Variable ZSensorOffset=ZSensorVolts(StartRetractTime)
	
	Variable StartTime=StartRetractTime+FishDetectionSettings[%MinDistance]/(-1*str2num(TriggerInfo[%RampSlope2])*GV("ZPiezoSens"))
	Variable EndTime=StartRetractTime+FishDetectionSettings[%MaxDistance]/(-1*str2num(TriggerInfo[%RampSlope2])*GV("ZPiezoSens"))
	
	Variable MinDefV=FishDetectionSettings[%DefVOffset]-(FishDetectionSettings[%MinForce]/GV("Invols")/GV("SpringConstant"))
	Variable MaxDefV=FishDetectionSettings[%DefVOffset]-(FishDetectionSettings[%MaxForce]/GV("Invols")/GV("SpringConstant"))
	
	Variable EndRetractTime=numpnts(DefVolts)*DeltaX(DefVolts)
	Variable CatchFish=0
	If(EndRetractTime>StartTime&&EndRetractTime>EndTime)
		WaveStats/Q/R=(StartTime,EndTime) DefVolts
		Variable MeasuredMinDef=V_min
		If(MeasuredMinDef<MinDefV&&MeasuredMinDef>=MaxDefV)
			CatchFish=1
		EndIf
	EndIf
	
	FishDetectionSettings[%DidWeCatchAFish]=CatchFish
	Duplicate/O FishDetectionSettings $("root:FRFishing:SavedData:FishDetectionsSettings"+num2str(FRFSettings[%Iteration]))
	
	Return CatchFish
End

 Function MakeSimpleFishDetectionWave([OutputWaveName])
	String OutputWaveName
	
	If(ParamIsDefault(OutputWaveName))
		OutputWaveName="FishDetectionSettings"
	EndIf

	Make/O/N=6 $OutputWaveName
	Wave FishDetectionSettings=$OutputWaveName
	
   	SetDimLabel 0,0, $"DefVOffset", FishDetectionSettings
   	SetDimLabel 0,1, $"MinDistance", FishDetectionSettings
   	SetDimLabel 0,2, $"MaxDistance", FishDetectionSettings
   	SetDimLabel 0,3, $"MinForce", FishDetectionSettings
   	SetDimLabel 0,4, $"MaxForce", FishDetectionSettings
      	SetDimLabel 0,5,$"DidWeCatchAFish", FishDetectionSettings
   	
	FishDetectionSettings={0,150e-9,250e-9,20e-12,250e-12,0}
End



 Function MakeFRFSettingsWave([OutputWaveName])
	String OutputWaveName
	
	If(ParamIsDefault(OutputWaveName))
		OutputWaveName="FRFSettings"
	EndIf

	Make/O/N=6 $OutputWaveName
	Wave FRFSettings=$OutputWaveName
	
   	SetDimLabel 0,0, $"DefVOffset", FRFSettings
   	SetDimLabel 0,1, $"Iteration", FRFSettings
   	SetDimLabel 0,2, $"UseSearchGrid", FRFSettings
   	SetDimLabel 0,3, $"StopFRF", FRFSettings
   	SetDimLabel 0,4, $"DoCatchFishAction", FRFSettings
      	SetDimLabel 0,5,$"UseZeroThePD", FRFSettings
   	
	FRFSettings={0,0,0,0,0,0}
End

Function MakeFRFWaveNamesCallback([OutputWaveName])
	String OutputWaveName
	
	If(ParamIsDefault(OutputWaveName))
		OutputWaveName="FRFWaveNamesCallback"
	EndIf

	Make/O/T/N=4 $OutputWaveName
	Wave/T FRFWaveNamesCallback=$OutputWaveName
	
 	SetDimLabel 0,0, $"ZSensor", FRFWaveNamesCallback
 	SetDimLabel 0,1, $"DefV", FRFWaveNamesCallback
 	SetDimLabel 0,2, $"Callback", FRFWaveNamesCallback
 	SetDimLabel 0,3, $"SaveName", FRFWaveNamesCallback

	FRFWaveNamesCallback={"root:FRFishing:ZSensor","root:FRFishing:DefV","","Molecule"}
End

Function DisplayFRFPanel(PanelName)
	String PanelName	

	DoWindow/F $PanelName
	If (V_flag==0)		
	Wave RampSettings=root:FRFishing:RampSettings
	Wave/T RampStrSettings=root:FRFishing:RampStrSettings

		StrSwitch(PanelName)
			Case "ForceRampFishingPanel":
				Execute/Q "ForceRampFishingPanel()"
				MoveWindow/W=ForceRampFishingPanel 250,5,388,295
			break
			Case "FRF_RampPanel":
				MakeForceRampPanel(RampSettings,RampStrSettings,PanelName="FRF_RampPanel",WindowName="FRF_Ramp")
				MoveWindow/W=FRF_RampPanel 400,10,550,285
			break
			
		EndSwitch
		
	EndIf

End

Window ForceRampFishingPanel() : Panel
	PauseUpdate; Silent 1		// building window...
	NewPanel /K=1 /W=(318,57,516,517) as "FRFishing"
	Button DoFRF_Button,pos={4,165},size={98,23},proc=FRFButtonProc,title="Go Fishing!"
	SetVariable DefVSV,pos={7,32},size={115,16},title="Defl Offset",format="%.0W1PV"
	SetVariable DefVSV,value= root:FRFishing:FRFSettings[%DefVOffset]
	SetVariable IterationSV,pos={7,56},size={141,16},title="Iteration"
	SetVariable IterationSV,value= root:FRFishing:FRFSettings[%Iteration],noedit= 1
	Button StopFRF_Button,pos={109,165},size={42,23},proc=FRFButtonProc,title="Stop"
	TitleBox Fishing_TB,pos={9,7},size={82,21},title="Fishing Settings"
	SetVariable CallbackSV,pos={5,77},size={140,16},title="Callback"
	SetVariable CallbackSV,value= root:FRFishing:FRFWaveNamesCallback[%Callback]
	Button SetOffset_Button,pos={125,31},size={26,17},proc=ForceClampButtonProc,title="Set"
	SetVariable SaveNameSV,pos={5,98},size={140,16},title="SaveName"
	SetVariable SaveNameSV,value= root:FRFishing:FRFWaveNamesCallback[%SaveName]
	CheckBox UseSearchGridCB,pos={1,119},size={96,14},proc=FRFCheckProc,title="Use Search Grid"
	CheckBox UseSearchGridCB,value= 1
	CheckBox PauseCB,pos={2,398},size={178,14},proc=FRFCheckProc,title="Execute action if we caught a fish"
	CheckBox PauseCB,value= 0
	Button ContinueFishing_Button,pos={4,194},size={98,23},proc=FRFButtonProc,title="Continue Fishing!"
	CheckBox UseZeroThePDCB,pos={3,140},size={98,14},proc=FRFCheckProc,title="Use Zero the PD"
	CheckBox UseZeroThePDCB,value= 1
	TitleBox Fishing_TB1,pos={4,224},size={117,21},title="Fish Detection Settings"
	SetVariable MinDistSV,pos={4,252},size={133,16},title="Min Distance"
	SetVariable MinDistSV,format="%.0W1Pm"
	SetVariable MinDistSV,limits={0,inf,1e-08},value= root:FRFishing:FishDetectionSettings[%MinDistance]
	SetVariable MaxDistSV,pos={4,275},size={132,16},title="Max Distance"
	SetVariable MaxDistSV,format="%.0W1Pm"
	SetVariable MaxDistSV,limits={0,inf,5e-08},value= root:FRFishing:FishDetectionSettings[%MaxDistance]
	SetVariable MinforceSV1,pos={4,298},size={132,16},title="Min Force"
	SetVariable MinforceSV1,format="%.0W1PN"
	SetVariable MinforceSV1,limits={0,inf,5e-12},value= root:FRFishing:FishDetectionSettings[%MinForce]
	SetVariable MaxForceSV,pos={4,321},size={132,16},title="Max Force"
	SetVariable MaxForceSV,format="%.0W1PN"
	SetVariable MaxForceSV,limits={0,inf,1e-11},value= root:FRFishing:FishDetectionSettings[%MaxForce]
	SetVariable CatchAFishSV,pos={4,346},size={140,16},title="Catch a Fish?"
	SetVariable CatchAFishSV,value= _STR:"No"
	TitleBox Fishing_TB2,pos={2,368},size={152,21},title="We caught a fish.  Now what?"
	PopupMenu CaughtFishActionMenu,pos={6,424},size={154,22},proc=FRFPopMenuProc,title="Caught Fish Action"
	PopupMenu CaughtFishActionMenu,mode=1,popvalue="Pause",value= #"\"Pause;Protein Daemon;\""
EndMacro


Function FRFCheckProc(cba) : CheckBoxControl
	STRUCT WMCheckboxAction &cba
	Wave FRFSettings=root:FRFishing:FRFSettings		

	switch( cba.eventCode )
		case 2: // mouse up
			Variable checked = cba.checked
			String CheckBoxName=cba.ctrlName
			Strswitch(CheckBoxName)
				case "UseSearchGridCB":
					FRFSettings[%UseSearchGrid]=checked
				break
				case "UseZeroThePDCB":
					FRFSettings[%UseZeroThePD]=checked
				break
				case "CaughtFishActionCB":
					FRFSettings[%DoCatchFishAction]=checked
				break
			EndSwitch
			

			break
		case -1: // control being killed
			break
	endswitch

	return 0
End

Function FRFButtonProc(ba) : ButtonControl
	STRUCT WMButtonAction &ba
	String ButtonName=ba.CtrlName
	Wave FRFSettings=root:FRFishing:FRFSettings		

	switch( ba.eventCode )
		case 2: // mouse up
			// click code here
				strswitch(ButtonName)
				case "DoFRF_Button":
					FRFSettings[%StopFRF]=0
					DoFRFishing()
				break
				case "StopFRF_Button":
					FRFSettings[%StopFRF]=1
				break 
				case "SetOffset_Button":
					DetermineFRFOffset()
				break 
				case "ContinueFishing_Button":
					If(FRFSettings[%UseSearchGrid]&&!FRFSettings[%UseZeroThePD])
						SearchForMolecule(FoundMolecule=1,Callback="DoFRFishing()")
					EndIf
					If(FRFSettings[%UseSearchGrid]&&FRFSettings[%UseZeroThePD])
						Wave/T ZeroThePDCallbackWave=root:ZeroThePD:ZeroThePDCallbackWave
						ZeroThePDCallbackWave[%Callback]="DoFRFishing()"
						SearchForMolecule(FoundMolecule=1,Callback="DoZeroPD()")
					EndIf
					If(!FRFSettings[%UseSearchGrid]&&FRFSettings[%UseZeroThePD])
						Wave/T ZeroThePDCallbackWave=root:ZeroThePD:ZeroThePDCallbackWave
						ZeroThePDCallbackWave[%Callback]="DoFRFishing()"
						DoZeroPD()
					EndIf
					If(!FRFSettings[%UseSearchGrid]&&!FRFSettings[%UseZeroThePD])
						DoFRFishing()
					EndIf
				break 


			EndSwitch

			break
		case -1: // control being killed
			break
	endswitch

	return 0
End


Function FRFPopMenuProc(pa) : PopupMenuControl
	STRUCT WMPopupAction &pa
	Wave/T FRFWaveNamesCallback=root:FRFishing:FRFWaveNamesCallback
	
	switch( pa.eventCode )
		case 2: // mouse up
			Variable popNum = pa.popNum
			String popStr = pa.popStr
			StrSwitch(popstr)
				case "Pause":
					FRFWaveNamesCallback[%Callback]=""
				break
				case "Protein Daemon":
					FRFWaveNamesCallback[%Callback]="InitDaemonRun()"
				break
			EndSwitch
			break
		case -1: // control being killed
			break
	endswitch

	return 0
End
