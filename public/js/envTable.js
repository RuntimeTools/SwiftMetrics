var request = "http://" + myurl + "/envRequest";

d3.select('#envDiv').append('p')
		.style("font-size", "18px")
        .style("padding-left", "45px")
        .style("padding-top", "20px")
        .style("padding-bottom", "5px")
		.text("Environment");
var paragraph = d3.select('#envDiv').append('p')
        .style("padding-left", "40px")
var table = paragraph.append('table')
		.style("font-size", "14px");
var thead = table.append('thead')
var tbody = table.append('tbody');

			

function populateEnvTable() {
	d3.json(request, function (error,data) {
		if (error) return console.warn(error);

        if (data == null)
        	return
  		function tabulate(data) {

			// create a row for each object in the data
			var rows = tbody.selectAll('tr')
			  .data(data)
			  .enter()
			  .append('tr');

			// create a cell in each row for each column
			var cells = rows.selectAll('td')
			  .data(function (row) {
			    return ['Parameter', 'Value'].map(function (column) {
			      return {column: column, value: row[column]};
			    });
			  })
			  .enter()
			  .append('td')
			    .text(function (d) { return d.value; });
	
		  return table;
		}
	
		// render the table(s)
		tabulate(data); // 2 column table

	});
}

setTimeout(setInterval(populateEnvTable(), 1200000), 3000);

