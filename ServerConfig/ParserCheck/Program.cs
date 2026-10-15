using System.Reflection;
using ScriptSystem;
using ScriptSystem.Consts;
using SystemModule;
OpenMir2.LogService.Logger = new Serilog.LoggerConfiguration().CreateLogger();
var parser = new ScriptParsers();
var method = typeof(ScriptParsers).GetMethod("LoadScriptFileQuestAction", BindingFlags.NonPublic | BindingFlags.Instance)!;
foreach (var test in new[] { ("MAPMOVE 11 187 301",ExecutionCode.MapMove), ("CLOSE",ExecutionCode.Close), ("BREAK",ExecutionCode.Break), ("GIVE item 1",ExecutionCode.Give) }) {
 object[] args2 = { test.Item1, new QuestActionInfo() };
 if (!(bool)method.Invoke(parser,args2)!) throw new Exception("Parse failed: "+test.Item1);
 var action=(QuestActionInfo)args2[1];
 if(action.nCmdCode!=(int)test.Item2) throw new Exception("Wrong action code: "+test.Item1);
 if(test.Item2==ExecutionCode.MapMove && (action.sParam1!="11" || action.nParam2!=187 || action.nParam3!=301)) throw new Exception("Wrong destination");
 Console.WriteLine("PASS "+test.Item2);
}



