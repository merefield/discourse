import Component from "@glimmer/component";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { htmlSafe } from "@ember/template";
import { modifier } from "ember-modifier";
import loadScript from "discourse/lib/load-script";
import { getColors } from "discourse/plugins/poll/lib/chart-colors";
import { PIE_CHART_TYPE } from "../components/modal/poll-ui-builder";

export default class PollResultsSankeyComponent extends Component {
  registerCanvasElement = modifier((element) => {
    this.canvasElement = element;
  });

  get canvasId() {
    return htmlSafe(`poll-results-chart-${this.args.id}`);
  }

  @action
  async drawSankey() {

    await loadScript("/javascripts/Chart.min.js");
    await loadScript("/plugins/poll/chartjs/chartjs-chart-sankey.min.js");

    const el = this.canvasElement;

    var labels = this.args.rankedChoiceOutcome.sankey_data.sankey_labels;

    function getColor(palette, name) {
      const node_id = name.split('_')[0];
      const item = palette.find(obj => obj.id === node_id);

      return item.color || "green";
    }

    this._chart = new Chart(el, {
      type: "sankey",
      data: {
        datasets: [
          {
            data: this.args.rankedChoiceOutcome.sankey_data.sankey_nodes,
            labels: labels,
            colorFrom: (c) => getColor(this.args.rankedChoiceOutcome.sankey_data.sankey_colours, c.dataset.data[c.dataIndex].from),
            colorTo: (c) => getColor(this.args.rankedChoiceOutcome.sankey_data.sankey_colours, c.dataset.data[c.dataIndex].to),
            borderWidth: 2,
            borderColor: 'black'
          }
        ]
      }
    });
  }
  <template>
    <div class="poll-results-chart">
      <canvas
        {{didInsert this.drawSankey}}
        {{didInsert this.registerCanvasElement}}
        id={{this.canvasId}}
        class="poll-results-canvas"
      ></canvas>
    </div>
  </template>
}
