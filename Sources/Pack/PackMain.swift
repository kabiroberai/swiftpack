import PackCLI

@main struct Main {
    static func main() async {
        await PackCommand.cancellableMain()
    }
}
