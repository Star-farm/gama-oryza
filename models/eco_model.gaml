/**
* Name: main
* Based on the internal empty template. 
* Author: pc
* Tags: 
*/


model main

/* Insert your model definition here */

global {
	file plot_shp <- file("../includes/Shapefile/an_bien_parcelles.shp");
	geometry shape <- envelope(plot_shp);
	image_file farmer_image <- file("../includes/farmer.png");
	
	matrix cf_s1;
	matrix awd_s1;
	
	//ORYZA op column
	int RUNNUM <- 0;
	int WRR14 <- 1;
	
	// Economic
	float rice_price <- 6500.0; // per kg
	float fert_cost <- 400000.0; // per ha
	float seed_cost <- 600000.0; // per ha
	float other_cost <- 300000.0; // per ha 
	
	// Decision parameters
	float adoption_threshold <- 0.1;
	int initial_awd_farmers <- 40;
	
	// Stats
	list<float> awd_adoption_rate <- [];
	list<float> mean_awd_income_per_ha <- [];
	list<float> mean_cf_income_per_ha <- [];
	
	// Simulation
	int current_season <- 1;
	int max_seasons <- 10;
	
	init {
		do load_data;
		
		create plot from: plot_shp with: [
			land_use :: string(read("Lu05_en")),
			plot_id :: string(read("ID_PARCELL")),
			area :: float(read("Area"))/10000 // Convert from m2 to ha
		];
		
		list<plot> rice_plots <- plot where (each.is_rice);
		create farmer number: length(rice_plots) {
			my_plot <- rice_plots[index];
			if (my_plot != nil) {
				my_plot.owner <- self;
				location <- my_plot.location;
			}
		}
		
		ask plot where (each.is_rice) {
			do identify_nearby_plots;
		}
		
		ask farmer {
			do identify_neighbors;
		}
		
		ask initial_awd_farmers among farmer {
			current_regime <- "AWD";
			write "Initial AWD farmer: " + name + " at plot " + my_plot.plot_id;
		}
		
		ask farmer {
			do update_yield_and_revenue;
		}
	}
	
	reflex season_cycle when: current_season <= max_seasons {
		write "Season " + current_season;
		ask farmer {
			previous_regime <- current_regime;
			previous_yield <- current_yield;
			previous_revenue <- current_revenue;
			previous_income <- current_income;
			previous_cost <- current_cost;
		}
		
		ask farmer {
			do update_yield_and_revenue;
		}
		
		ask farmer where (each.current_regime = "CF"){
			do decide_regime;
		}
		
		do collect_stats;
			current_season <- current_season + 1;
	}
	
	action load_data {
		cf_s1 <- csv_file("../includes/Results/CF_s1/cf_op.csv");
		awd_s1 <- csv_file("../includes/Results/AWD_s1/awd_op.csv");
	}
	
	float get_yield(string regime, int season){
		matrix data_source; 
		if (regime = "CF"){
			data_source <- cf_s1;
		} else {
			data_source <- awd_s1;
		}
		
		list<float> yield_values <- get_column_values(data_source, WRR14);
		
		if (season - 1 < data_source.rows) {
			return float(data_source[WRR14, season - 1]);
		}
		return 0.0;
	}
	
	list<float> get_column_values(matrix data, int col_index) {
		list<float> values <- [];
		loop i from: 0 to: data.rows - 1{
			values <- values + float(data[col_index, i]);
		}
		return values;
	}
	
	action collect_stats {
		int cf_count <- length(farmer where (each.current_regime = "CF"));
		int awd_count <- length(farmer where (each.current_regime = "AWD"));
		int total_farmers <- length(farmer);
		add (awd_count/total_farmers) to: awd_adoption_rate;
		
		list<farmer> cf_farmers <- farmer where (each.current_regime = "CF");
		if (length(cf_farmers)>0) {
			float total_cf_income_per_ha <- sum(cf_farmers collect (each.current_income / each.my_plot.area));
			add (total_cf_income_per_ha / length(cf_farmers)) to: mean_cf_income_per_ha;
		}
		
		list<farmer> awd_farmers <- farmer where (each.current_regime = "AWD");
		if (length(awd_farmers)>0) {
			float total_awd_income_per_ha <- sum(awd_farmers collect (each.current_income / each.my_plot.area));
			add (total_awd_income_per_ha / length(awd_farmers)) to: mean_awd_income_per_ha;
		}
	}	
}

species plot {
	string land_use;
	string plot_id;
	float area; //ha 			
	farmer owner;
	list<plot> nearby_plots <- [];
	
	bool is_rice <- (land_use != nil) and (land_use contains "Rice");
	
	action identify_nearby_plots {
		if (shape != nil) {
			nearby_plots <- plot where (
				each != self and
				each.is_rice and
				each.shape != nil and
				self.shape intersects each.shape
			);
		}
	}
	
	aspect default {
		if (is_rice and owner != nil) {
			draw shape color: (owner.current_regime = "AWD") ? #lightgreen : #darkgreen border: #black;
		} else {
			draw shape color: #gray border: #black;
		}
	}
}

species farmer {
	plot my_plot;
	string current_regime <- "CF"; // or AWD
	string previous_regime <- "CF";
	list<farmer> neighbors <- [];
	
	float current_yield <- 0.0;
	float previous_yield <- 0.0;

	float current_cost <- 0.0;
	float previous_cost <- 0.0;
	
	float current_income <- 0.0;
	float previous_income <- 0.0;
	
	float current_revenue <- 0.0;
	float previous_revenue <- 0.0;
	
	action identify_neighbors {
		if (my_plot != nil) {
			neighbors <- [];
			loop nearby_plot over: my_plot.nearby_plots{
				if (nearby_plot.owner != nil and nearby_plot.owner != self) {
					add nearby_plot.owner to: neighbors;
				}
			}
		}
		write name + " has " + length(neighbors) + " neighbors";
	}
	
	action update_yield_and_revenue {
		if (my_plot != nil) {
			matrix data_source;
			if (current_regime = "CF") {
				data_source <- cf_s1;
			} else {
				data_source <- awd_s1;
			}
			current_yield <- float(data_source[WRR14, current_season - 1]);
			current_revenue <- current_yield * (my_plot.area) * rice_price; // yield(kg/ha)*area(ha)*price(VND/kg)
			current_cost <- (seed_cost + fert_cost + other_cost)*(my_plot.area);
			current_income <- current_revenue - current_cost;
		}
	}
	
	action decide_regime {
		list<farmer> awd_neighbors <- neighbors where (each.current_regime = "AWD");
		if (length(awd_neighbors) > 0){
			float mean_awd_current_income <- mean(awd_neighbors collect each.current_income);
			list<farmer> awd_neighbors_last <- neighbors where (each.previous_regime = "AWD");	
			if (length(awd_neighbors_last) > 0) {
				float mean_awd_previous_income <- mean(awd_neighbors_last collect each.previous_income);
				float income_growth_ratio <- 0.0;
				if (mean_awd_previous_income> 0) {
					income_growth_ratio <- (mean_awd_current_income - mean_awd_previous_income) / mean_awd_previous_income;
				}
				
				if (income_growth_ratio >= adoption_threshold) {
					current_regime <- "AWD";
				}
			}
		}
	}
	
	aspect default {
		if (my_plot != nil) {
			draw farmer_image size: {50, 50} color: (current_regime = "AWD") ? #red : #blue;
		}
	}
}

experiment Run type: gui {
	float minimum_cycle_duration <- 5#s;
	parameter "Rice price (VND/kg)" var: rice_price min: 5000.0 max: 12000.0 step: 500.0;
	parameter "Fertilizer cost (VND/ha)" var: fert_cost min: 300000.0 max: 800000.0 step: 50000.0;
	parameter "Seed cost (VND/ha)" var: seed_cost min: 400000.0 max: 800000.0 step: 50000.0;
	parameter "Other cost (VND/ha)" var: other_cost min: 100000.0 max: 500000.0 step: 50000.0;
	parameter "Adoption threshold" var: adoption_threshold min: 0.05 max: 1.0 step: 0.05;
	parameter "Initial AWD farmers" var: initial_awd_farmers min: 1 max: 50 step:1;
	
	output{
		display plot_display {
			species plot aspect: default;
			species farmer aspect: default;
		}
		
		display stats type: 2d {
			chart "AWD adoption rate" type: series {
				data "AWD adoption rate" value: awd_adoption_rate color: #blue;
			}
		}
		
		display income_per_ha type: 2d{
			chart "Income per ha" type: series {
				data "AWD Income" value: mean_awd_income_per_ha color: #red;
				data "CF Income" value: mean_cf_income_per_ha color: #blue;
			}
		}
		
		monitor "Current Season" value: current_season;
		monitor "CF Farmers " value: length(farmer where (each.current_regime = "CF"));
		monitor "AWD Farmers " value: length(farmer where (each.current_regime = "AWD"));
		
	}
}