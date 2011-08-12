#region license
// Copyright (c) 2003, 2004, 2005 Rodrigo B. de Oliveira (rbo@acm.org)
// All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
// 
//     * Redistributions of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//     * Neither the name of Rodrigo B. de Oliveira nor the names of its
//     contributors may be used to endorse or promote products derived from this
//     software without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
// THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#endregion

namespace UnityScript.Build.Tasks

import Microsoft.Build.Framework
import Microsoft.Build.Tasks
import Microsoft.Build.Utilities
import System
import System.Diagnostics
import System.IO
import System.Globalization
import System.Text.RegularExpressions
import System.Threading

class US(ManagedCompiler):

	BaseClass:
		get:
			return Bag['BaseClass'] as string
		set:
			Bag['BaseClass'] = value

	DisableEval:
		get:
			return GetBoolParameterWithDefault("DisableEval", false)
		set:
			Bag['DisableEval'] = value

	Expando:
		get:
			return GetBoolParameterWithDefault("Expando", false)
		set:
			Bag['Expando'] = value

	Imports:
		get:
			return Bag['Imports'] as (string)
		set:
			Bag['Imports'] = value

	Pragmas:
		get:
			return Bag['Pragmas'] as string
		set:
			Bag['Pragmas'] = value

	Method:
		get:
			return Bag['Method'] as string
		set:
			Bag['Method'] = value

	Verbose:
		get:
			return GetBoolParameterWithDefault('Verbose', false)
		set:
			Bag['Verbose'] = value

	TypeInferenceRuleAttribute:
		get:
			return Bag['TypeInferenceRuleAttribute'] as string
		set:
			Bag['TypeInferenceRuleAttribute'] = value

	SuppressedWarnings:
		get:
			return Bag['SuppressedWarnings'] as (string)
		set:
			Bag['SuppressedWarnings'] = value

	SourceDirectories:
		get:
			return Bag['Source Directories'] as (string)
		set:
			Bag['Source Directories'] = value
	
	DefineSymbols:
		get:
			return Bag['DefineSymbols'] as string
		set:
			Bag['DefineSymbols'] = value
	
	ToolName:
		get:
			return "us.exe"
			
	GenerateFullPaths:
		get:
			return GetBoolParameterWithDefault("GenerateFullPaths", false)
		set:
			Bag["GenerateFullPaths"] = value
		
	
	override def Execute():

		usCommandLine = CommandLineBuilderExtension()
		AddResponseFileCommands(usCommandLine)
		
		warningPattern = regex(
			'^(?<file>.*?)(\\((?<line>\\d+),(?<column>\\d+)\\):)?' +
				'(\\s?)(?<code>BCW\\d{4}):(\\s)WARNING:(\\s)(?<message>.*)$',
			RegexOptions.Compiled)
		# Captures the file, line, column, code, and message from a BOO warning
		# in the form of: Program.boo(1,1): BCW0000: WARNING: This is a warning.
		
		errorPattern = regex(
			'^(((?<file>.*?)\\((?<line>\\d+),(?<column>\\d+)\\): )?' +
				'(?<code>BCE\\d{4})|(?<errorType>Fatal) error):' +
				'( Boo.Lang.Compiler.CompilerError:)?' + 
				' (?<message>.*?)($| --->)',
			RegexOptions.Compiled |
				RegexOptions.ExplicitCapture |
				RegexOptions.Multiline)
		/* 
		 * Captures the file, line, column, code, error type, and message from a
		 * BOO error of the form of:
		 * 1. Program.boo(1,1): BCE0000: This is an error.
		 * 2. Program.boo(1,1): BCE0000: Boo.Lang.Compiler.CompilerError:
		 *    	This is an error. ---> Program.boo:4:19: This is an error
		 * 3. BCE0000: This is an error.
		 * 4. Fatal error: This is an error.
		 *
		 * The second line of the following error format is not cought because 
		 * .NET does not support if|then|else in regular expressions,
		 * and the regex will be horrible complicated.  
		 * The second line is as worthless as the first line.
		 * Therefore, it is not worth implementing it.
		 *
		 * 	Fatal error: This is an error.
		 * 	Parameter name: format.
		 */
		
		buildSuccess = true
		outputLine = String.Empty
		errorLine = String.Empty
		readingDoneEvents = (ManualResetEvent(false), ManualResetEvent(false))
		
		usProcessStartInfo = ProcessStartInfo(
			FileName: GenerateFullPathToTool(),
			Arguments: usCommandLine.ToString(),
			ErrorDialog: false,
			CreateNoWindow: true,
			RedirectStandardError: true,
			RedirectStandardInput: false,
			RedirectStandardOutput: true,
			UseShellExecute: false)
		
		usProcess = Process(StartInfo: usProcessStartInfo)
		
		parseOutput = def(line as string):
			warningPatternMatch = warningPattern.Match(line)
			errorPatternMatch = errorPattern.Match(line)
		
			if warningPatternMatch.Success:
				lineOut = 0
				columnOut = 0
				int.TryParse(warningPatternMatch.Groups['line'].Value, lineOut)
				int.TryParse(warningPatternMatch.Groups['column'].Value, columnOut)
				Log.LogWarning(
					null,
					warningPatternMatch.Groups['code'].Value,
					null,
					GetFilePathToWarningOrError(warningPatternMatch.Groups['file'].Value),
					lineOut,
					columnOut,
					0,
					0,
					warningPatternMatch.Groups['message'].Value)
		
			elif errorPatternMatch.Success:					
				code = errorPatternMatch.Groups['code'].Value
				code = 'BCE0000' if string.IsNullOrEmpty(code)
				file = GetFilePathToWarningOrError(errorPatternMatch.Groups['file'].Value)
				file = 'BOOC' if string.IsNullOrEmpty(file)
				
				try:
					lineNumber = int.Parse(
						errorPatternMatch.Groups['line'].Value,
						NumberStyles.Integer)
						
				except as FormatException:
					lineNumber = 0

				try:
					columnNumber = int.Parse(
						errorPatternMatch.Groups['column'].Value,
						NumberStyles.Integer)
						
				except as FormatException:
					columnNumber = 0

				Log.LogError(
					errorPatternMatch.Groups['errorType'].Value.ToLower(),
					code,
					null,
					file,
					lineNumber,
					columnNumber,
					0,
					0,
					errorPatternMatch.Groups['message'].Value)
		
				buildSuccess = false
		
			else:
				Log.LogMessage(MessageImportance.Normal, line)
				
		readStandardOutput = def():
			while true:
				outputLine = usProcess.StandardOutput.ReadLine()
		
				if outputLine:
					parseOutput(outputLine)
					
				else:
					readingDoneEvents[0].Set()
					break

		readStandardError = def():
			while true:
				errorLine = usProcess.StandardError.ReadLine()

				if errorLine:
					parseOutput(errorLine)
					
				else:
					readingDoneEvents[1].Set()
					break
		
		standardOutputReadingThread = Thread(readStandardOutput as ThreadStart)	
		standardErrorReadingThread = Thread(readStandardError as ThreadStart)
		# Two threads are required (MSDN); otherwise, a deadlock WILL occur.
		
		try:
			usProcess.Start()
			
			Log.LogMessage(
				MessageImportance.High,
				"${ToolName} ${usProcess.StartInfo.Arguments}",
				null)
				
			standardOutputReadingThread.Start()
			standardErrorReadingThread.Start()
			
			WaitHandle.WaitAny((readingDoneEvents[0],))
			WaitHandle.WaitAny((readingDoneEvents[1],))
			# MSBuild runs on an STA thread, and WaitHandle.WaitAll()
			# is not supported.
			
			usProcess.WaitForExit()
			if usProcess.ExitCode != 0:
				if buildSuccess:
					// Report an error if us exits with error code but we didn't
					// receive any error.
					Log.LogError("us exited with code ${usProcess.ExitCode}")
				buildSuccess = false
		except e as Exception:
			Log.LogErrorFromException(e)
			buildSuccess = false
			
		ensure:
			usProcess.Close()

		return buildSuccess
	
	protected override def AddCommandLineCommands(commandLine as CommandLineBuilderExtension):
			pass
	
	protected override def AddResponseFileCommands(commandLine as CommandLineBuilderExtension):
		commandLine.AppendSwitchIfNotNull('-base:', BaseClass)
		commandLine.AppendSwitchIfNotNull('-method:', Method)
		commandLine.AppendSwitchIfNotNull('-t:', TargetType)
		commandLine.AppendSwitchIfNotNull('-o:', OutputAssembly)
		commandLine.AppendSwitchIfNotNull('-define:', DefineSymbols)
		commandLine.AppendSwitchIfNotNull('-pragmas:', Pragmas)
		commandLine.AppendSwitchIfNotNull("-lib:", AdditionalLibPaths, ",")
		
		if NoConfig:
			commandLine.AppendSwitch('-noconfig')
		
		if EmitDebugInformation:
			commandLine.AppendSwitch('-debug+')
		else:
			commandLine.AppendSwitch('-debug-')

		if Expando:
			commandLine.AppendSwitch('-expando+')
		else:
			commandLine.AppendSwitch('-expando-')

		if DisableEval:
			commandLine.AppendSwitch('-disable-eval:disable-eval')

		commandLine.AppendSwitchIfNotNull("-x-type-inference-rule-attribute:", TypeInferenceRuleAttribute)

		if SourceDirectories:
			for sd in SourceDirectories:
				commandLine.AppendSwitchIfNotNull("-srcdir:", sd)

		if SuppressedWarnings:
			for sw in SuppressedWarnings:
				commandLine.AppendSwitchIfNotNull("-nowarn:", sw)

		if Imports:
			for imp in Imports:
				commandLine.AppendSwitchIfNotNull("-import:", imp)
				
		if ResponseFiles:
			for rsp in ResponseFiles:
				commandLine.AppendSwitchIfNotNull("@", rsp.ItemSpec)				

		if References:
			for reference in References:
				commandLine.AppendSwitchIfNotNull('-r:', reference.ItemSpec)
				
		if Resources:
			for resource in Resources:
				commandLine.AppendSwitchIfNotNull('-resource:', resource.ItemSpec)
		
		if Verbose:
			commandLine.AppendSwitch('-verbose+')
		else:
			commandLine.AppendSwitch('-verbose-')
					
		commandLine.AppendFileNamesIfNotNull(Sources, ' ')
		
	protected override def GenerateFullPathToTool():
		path = ""
		
		if ToolPath:
			path = Path.Combine(ToolPath, ToolName)
		
		return path if File.Exists(path)
		
		path = ToolLocationHelper.GetPathToDotNetFrameworkFile(
			ToolName,
			TargetDotNetFrameworkVersion.VersionLatest)
		
		return path if File.Exists(path)

		path = "us"
						
		return path
	
	private def GetFilePathToWarningOrError(file as string):
		if GenerateFullPaths:
			return Path.GetFullPath(file)
		else:
			return file
