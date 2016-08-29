var express = require('express');
var http = require('http');
var router = express.Router();
var fs = require('fs');
var cityArray = ["Omaha,NE","NY/New_York","SG/Singapore","ID/Jakarta"];
var key = '69098eef7b6a263c';

/* Set http option */
var options = {
  host: 'api.wunderground.com',
  path: ''
};

/* GET Home page. */
router.get('/', function(req, res, next) {
  //redirect to weather page
  res.redirect("weather");
});

/* GET Weatherlist page. */
router.get('/weather', function(req, res) {
    // Set our internal DB variable
	var db = req.db;
    // Set our collection
	var collection = db.get('weathercollection');
    collection.find({},{},function(e,docs){
        res.render('weather', {
            "weather" : docs
        });
    });
});

/* GET Update page. */
router.get('/updateweather', function(req, res) {
	// Set our internal DB variable
    var db = req.db;
	// Set our collection
    var collection = db.get('weathercollection');
	
	var jsonObject;
	var jsonWeather;
	var i;
	//loop for each city
	for (i = 0; i < cityArray.length; i++) {
		//set correct url path
		options.path = '/api/' + key + '/conditions/q/' + cityArray[i] + '.json'
		var call = http.request(options, function(response){
			if(response.statusCode == 200) {
				var str = '';
				//retrieve chunk
				response.on('data', function (chunk) {
					str += chunk;
				});

				//get the whole data
				response.on('end', function () {
					//parse into json object
					jsonObject = JSON.parse(str);
					//update correct data collection
					collection.update({"key":jsonObject.current_observation.display_location.city}, {$set:{updateStatus:"Success",data:jsonObject.current_observation.weather,lastUpdate:new Date()}}, function (err, doc) {
						//if write failed
						if (err) {
							//if it failed, return error
							res.send("There was a problem adding the information to the database.");
							console.log('There was a problem adding the information to the database.');
						}
						//if write success
						else {
							//write a log on console
							console.log('Success update ' + jsonObject.current_observation.display_location.city);
						}
					})
					//log all parameter passed to server
					fs.appendFile("log/file", "Successfully get new data for " + jsonObject.current_observation.display_location.city + " on " + new Date() + "\n" + JSON.stringify(jsonObject) + "\n", function(err) {
						if(err) {
							return console.log(err);
						}
						//write a log on console
						console.log("Log file was appended!");
					}); 					
				});
			}
			else {
				//if it failed to retrieve data, update status
				collection.update({"key":cityArray[i]}, {$set:{updateStatus:"Failed"}});
			}
		});
		//error handler
		call.on('error', (e) => {
		  console.log("Error");
		}); 	
		//end http request
		call.end();
	}
	delete require.cache['/weather'];
	
	//redirect to home page
	res.redirect('back');
});

module.exports = router;
