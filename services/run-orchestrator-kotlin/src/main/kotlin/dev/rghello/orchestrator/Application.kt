package dev.rghello.orchestrator

import java.io.PrintStream
import kotlin.system.exitProcess

var exit: (Int) -> Unit = { code -> exitProcess(code) }

fun main(args: Array<String>) {
    exit(run(System.out, System.err, args))
}

fun run(
    out: PrintStream,
    err: PrintStream,
    args: Array<String>,
): Int {
    if (args.size == 1 && args[0] == "version") {
        out.println("${Version.SERVICE_NAME} ${Version.VERSION}")
        return 0
    }
    err.println("${Version.SERVICE_NAME}: Milestone 0 skeleton - functionality not implemented yet")
    err.println("usage: ${Version.SERVICE_NAME} version")
    return 0
}
