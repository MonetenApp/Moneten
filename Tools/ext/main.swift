import ExtensionHost
import Foundation

if CommandLine.arguments.dropFirst() == [Ext.hostArgument] {
	HostProcess.serve()
	exit(0)
}

let status = await Ext.main(Array(CommandLine.arguments.dropFirst()))
fflush(stdout)
exit(status)
