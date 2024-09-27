import Component from "@glimmer/component";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { htmlSafe } from "@ember/template";
import { modifier } from "ember-modifier";
import loadScript from "discourse/lib/load-script";
import { getColors } from "discourse/plugins/poll/lib/chart-colors";
import { PIE_CHART_TYPE } from "../components/modal/poll-ui-builder";

export default class PollResultsSankeyComponent extends Component {
  htmlLegendPlugin = {
    id: "htmlLegend",

    // afterUpdate(chart, args, options) {
    //   const ul = document.getElementById(options.containerID);
    //   if (!ul) {
    //     return;
    //   }

    //   ul.innerHTML = "";

    //   const items = chart.options.plugins.legend.labels.generateLabels(chart);
    //   items.forEach((item) => {
    //     const li = document.createElement("li");
    //     li.classList.add("legend");
    //     li.onclick = () => {
    //       chart.toggleDataVisibility(item.index);
    //       chart.update();
    //     };

    //     const boxSpan = document.createElement("span");
    //     boxSpan.classList.add("swatch");
    //     boxSpan.style.background = item.fillStyle;

    //     const textContainer = document.createElement("span");
    //     textContainer.style.color = item.fontColor;
    //     textContainer.innerHTML = item.text;

    //     if (!chart.getDataVisibility(item.index)) {
    //       li.style.opacity = 0.2;
    //     } else {
    //       li.style.opacity = 1.0;
    //     }

    //     li.appendChild(boxSpan);
    //     li.appendChild(textContainer);

    //     ul.appendChild(li);
    //   });
    // },
  };

  stripHtml = (html) => {
    let doc = new DOMParser().parseFromString(html, "text/html");
    return doc.body.textContent || "";
  };

  pieChartConfig = (data, labels, opts = {}) => {
    const aspectRatio = "aspectRatio" in opts ? opts.aspectRatio : 2.2;
    const strippedLabels = labels.map((l) => this.stripHtml(l));

    return {
      type: PIE_CHART_TYPE,
      data: {
        datasets: [
          {
            data,
            backgroundColor: getColors(data.length),
          },
        ],
        labels: strippedLabels,
      },
      plugins: [this.htmlLegendPlugin],
      options: {
        responsive: true,
        aspectRatio,
        animation: { duration: 0 },
        plugins: {
          legend: {
            labels: {
              generateLabels() {
                return labels.map((text, index) => {
                  return {
                    fillStyle: getColors(data.length)[index],
                    text,
                    index,
                  };
                });
              },
            },
            display: false,
          },
          htmlLegend: {
            containerID: opts?.legendContainerId,
          },
        },
      },
    };
  };

  registerLegendElement = modifier((element) => {
    this.legendElement = element;
  });
  registerCanvasElement = modifier((element) => {
    this.canvasElement = element;
  });
  get canvasId() {
    return htmlSafe(`poll-results-chart-${this.args.id}`);
  }

  // get legendId() {
  //   return htmlSafe(`poll-results-legend-${this.args.id}`);
  // }

  @action
  async drawSankey() {

    await loadScript("/javascripts/Chart.min.js");
    await loadScript("/plugins/poll/chartjs/chartjs-chart-sankey.min.js");
    // debugger;
    // const data = this.args.rankedChoiceOutcome.mapBy("votes");
    // const labels = this.args.rankedChoiceOutcome.mapBy("html");
    // const config = this.pieChartConfig(data, labels, {
    //   legendContainerId: this.legendElement.id,
    // });
    const el = this.canvasElement;
    // eslint-disable-next-line no-undef
//     var ctx = document.getElementById("chart").getContext("2d");
// var ctx2 = document.getElementById("chart2").getContext("2d");

    // var colors = {
    //   Oil: "black",
    //   Coal: "gray",
    //   "Fossil Fuels": "slategray",
    //   Electricity: "blue",
    //   Energy: "orange"
    // };

    // the y-order of nodes, smaller = higher
    // var priority = {
    //   Oil: 1,
    //   'Narural Gas': 2,
    //   Coal: 3,
    //   'Fossil Fuels': 1,
    //   Electricity: 2,
    //   Energy: 1
    // };

    // var labels = {
    //   Oil: 'black gold (label changed)'
    // };

    // var labels = {
    //   Oil: 'black gold (label changed)'
    // };

    // var labels = {
    //   N8444417da46921d008fc634686a86932_1: "Joist",
    //   N8444417da46921d008fc634686a86932_2: "Joist",
    //   N8444417da46921d008fc634686a86932_3: "Joist",

    // }

    var labels = this.args.rankedChoiceOutcome.sankey_data.sankey_labels;

    function getColor(name) {
      return colors[name] || "green";
    }
debugger;
    this._chart = new Chart(el, {
      type: "sankey",
      data: {
        datasets: [
          {
            data: this.args.rankedChoiceOutcome.sankey_data.sankey_nodes,
            labels: labels,
            // [ 
              // { from: "Oil", to: "Fossil Fuels", flow: 15 },
              // { from: "Natural Gas", to: "Fossil Fuels", flow: 20 },
              // { from: "Coal", to: "Fossil Fuels", flow: 25 },
              // { from: "Coal", to: "Electricity", flow: 25 },
              // { from: "Fossil Fuels", to: "Energy", flow: 60 },
              // { from: "Electricity", to: "Energy", flow: 25 }
            // ],
            // priority,
            // labels,
            // colorFrom: (c) => getColor(c.dataset.data[c.dataIndex].from),
            // colorTo: (c) => getColor(c.dataset.data[c.dataIndex].to),
            borderWidth: 2,
            borderColor: 'black'
          }
        ]
      }
    });

    // this._chart = new Chart(el.getContext("2d"), config);
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
