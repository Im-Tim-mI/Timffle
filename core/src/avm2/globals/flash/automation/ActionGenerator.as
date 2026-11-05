package flash.automation {
    // Timffle: `flash.automation` only acts in the automation-enabled Flash Player (the test
    // automation build). This is the normal player: the classes exist with their documented
    // members, but generating an action injects nothing -- no synthetic keyboard or mouse
    // event reaches the stage -- exactly as in the shipping Flash Player, where the package
    // is present in playerglobal but inert. Flash Player 32 accepts null too (measured).
    [API("667")]
    public class ActionGenerator {
        public function ActionGenerator() {
        }

        public function generateAction(action:AutomationAction):void {
        }

        public function generateActions(actions:Vector.<AutomationAction>):void {
        }
    }
}
