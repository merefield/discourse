import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import DropdownSelectBox from "select-kit/components/dropdown-select-box";
import { hash } from "@ember/helper";
import { fn } from "@ember/helper";

export default class PollOptionsDropdownComponent extends Component {
  @tracked rank = 0;
  constructor() {
    super(...arguments);
    this.rank = this.args.rank;
  }

  @action
  selectRank(option, rank) {
    this.rank = rank;
    this.args.sendRank(option, rank);
  }
  <template>
    <div class="irv-dropdown">
      <DropdownSelectBox
        @candidate={{@option.id}}
        @value={{this.rank}}
        @content={{@irvDropdownContent}}
        @onChange={{fn this.selectRank @option.id}}
        @options={{hash showCaret=true filterable=false}}
        class="poll-option-dropdown"
      />
    </div>
  </template>
}
