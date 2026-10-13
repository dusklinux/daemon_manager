import Foundation

@main
struct ElevatedCommandTests {
    static func main() {
        let password = "spaces ' \" $literal `literal` \\ end"
        let command = "printf '%s\\n' 'an apostrophe: '\\'' and $literal'"
        let sudo = ElevatedCommand.build(command: command, password: password, shell: "/bin/sh",
            sudo: "/sudo", python: "/python", hasSudo: true)
        precondition(sudo.executable == "/sudo")
        precondition(sudo.arguments == ["-S", "-p", "", "--", "/bin/sh", "-c", command])
        precondition(sudo.standardInput == password + "\n")
        precondition(!sudo.arguments.contains(password), "Password must travel over stdin")
        let su = ElevatedCommand.build(command: command, password: password, shell: "/bin/sh",
            sudo: "/sudo", python: "/python", hasSudo: false)
        precondition(su.arguments.last == command, "su must receive the unescaped original command")
        precondition(su.standardInput == sudo.standardInput)
        precondition(!su.arguments.contains(password))
        print("Literal password stdin and unchanged sudo/su command forwarding passed")
    }
}
