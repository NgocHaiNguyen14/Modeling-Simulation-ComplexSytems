/**
* Name: FluVirus
* Description: Model of flu virus spread in a city with isolation measures
*/

model FluVirus

global {
    // import GIS data
    shape_file shapefile_buildings <- shape_file("../includes/buildings.shp");
    shape_file shapefile_roads <- shape_file("../includes/clean_roads.shp");
    
    // Environment
    geometry shape <- envelope(shapefile_roads);
    graph road_network;
    
    // Population parameters
    int nb_people <- 12000;
    float infection_probability <- 0.33; // 33% chance of infection when in contact
    int isolation_duration <- 12;  // days
    float test_percentage <- 0.01; // 1% of population tested daily
    
    // Simulation step
    float step <- 1 #hour;
    
    // Time management
    int start_work <- 8;
    int end_work <- 17;
    bool is_working_hour <- false update: current_date.hour >= start_work and current_date.hour < end_work;
    
    init {
        // Create buildings and roads
        create building from: shapefile_buildings;
        create road from: shapefile_roads;
        road_network <- as_edge_graph(road);
        
        // Create initial population
        create person number: nb_people {
            // Assign home and workplace
            home <- any_location_in(one_of(building));
            workplace <- any_location_in(one_of(building));
            location <- home;
            
            // Initialize as susceptible
            is_infected <- false;
            is_isolated <- false;
        }
        
        // Initialize with some infected people
        ask (nb_people * 0.01) among person { // Start with 1% infected
            is_infected <- true;
            infection_time <- current_date;
        }
    }
    
    // Daily testing reflex
    reflex daily_testing when: every(24 #hour) {	
        list<person> untested_people <- person where (!each.is_isolated);
        int num_to_test <- max(1, int(length(untested_people) * test_percentage));
        ask num_to_test among untested_people {
            if (is_infected) {
                is_isolated <- true;
                isolation_start <- current_date;
            }
        }
    }
}

species building {
    aspect default {
        draw shape color: #gray;
    }
}

species road {
    aspect default {
        draw shape color: #black;
    }
}

species person skills: [moving] {
    // Locations
    point home;
    point workplace;
    point target;
    
    // Disease status
    bool is_infected <- false;
    bool is_isolated <- false;
    date infection_time;
    date isolation_start;
    int infection_duration <- rnd(2,8); // Random duration between 2-8 days
    
    // Movement
    float speed <- 30 #km/#h;
    
    reflex go_to_work when: !is_isolated and is_working_hour and location = home {
        target <- workplace;
    }
    
    reflex return_home when: !is_isolated and !is_working_hour and location = workplace {
        target <- home;
    }
    
    reflex move when: target != nil {
        do goto target: target on: road_network;
        if (location distance_to target < 2#m) {
            location <- target;
            target <- nil;
        }
    }
    
    // Disease dynamics
    reflex infect when: is_infected and !is_isolated {
        ask person at_distance 2#m where (!each.is_infected and !each.is_isolated) {
            if flip(infection_probability) {
                is_infected <- true;
                infection_time <- current_date;
            }
        }
    }
    
    reflex recover when: is_infected and !is_isolated {
        if (current_date - infection_time > infection_duration #day) {
            is_infected <- false;
        }
    }
    
    reflex end_isolation when: is_isolated {
        if (current_date - isolation_start > isolation_duration #day) {
            is_isolated <- false;
        }
    }
    
    aspect default {
        draw circle(5) color: is_isolated ? #gray : (is_infected ? #red : #green);
    }
}

experiment flu_simulation type: gui {
    parameter "Number of people" var: nb_people min: 1000 max: 20000 category: "Population";
    parameter "Infection probability" var: infection_probability min: 0.0 max: 1.0 category: "Disease";
    parameter "Test percentage" var: test_percentage min: 0.0 max: 0.1 category: "Control";
    
    output {
        display city_display {
            species building aspect: default;
            species road aspect: default;
            species person aspect: default;
        }
        
        display charts {
            chart "Disease Status" type: series {
                data "Infected" value: person count (each.is_infected) color: #red;
                data "Susceptible" value: person count (!each.is_infected) color: #green;
                data "Isolated" value: person count (each.is_isolated) color: #gray;
            }
        }
    }
}
