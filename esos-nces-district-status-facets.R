library(sf)
library(stringi)
library(hrbragg) # github.com/hrbrmstr/hrbragg
library(tidyverse)

state_meta <- jsonlite::stream_in(file("~/projects/2021-esos-nces/us-fips-metadata.json"))

edge_c <- st_read("~/projects/2021-esos-nces/nces-edge-centroids.geojson")

edge_c %>% 
  left_join(state_meta, by = "STATEFP") -> edge_c

cols(
  `State name` = col_character(),
  `State abbreviation` = col_character(),
  `State FIPS code` = col_character(),
  `NCES district ID` = col_character(),
  `School district name` = col_character(),
  `In person` = col_double(),
  `Fully remote` = col_double(),
  `Hybrid: part day` = col_double(),
  `Hybrid: part week` = col_double(),
  `Hybrid: rotating weeks` = col_double(),
  `Hybrid: other` = col_double(),
  Notes = col_character(),
  `Date collected` = col_character(),
  `Data source` = col_character(),
  `Estimated total population` = col_double(),
  `Estimated population ages 5 to 17` = col_double(),
  `Estimated number of children ages 5 to 17 in poverty` = col_double(),
  `Share of children 5 to 17 in poverty` = col_double(),
  `Kindergarten students` = col_character(),
  `Grade 1 students` = col_character(),
  `Grade 2 students` = col_character(),
  `Grade 3 students` = col_character(),
  `Grade 4 students` = col_character(),
  `Grade 5 students` = col_character(),
  `Grade 6 students` = col_character(),
  `Total elementary students` = col_character(),
  `American Indian/Alaska Native students` = col_character(),
  `Asian or Asian/Pacific Islander students` = col_character(),
  `Hispanic students` = col_character(),
  `Black students` = col_character(),
  `White students` = col_character(),
  `Hawaiian Nat./Pacific Isl. students` = col_character(),
  `Two or more races students` = col_character(),
  `Total race/ethnicity` = col_character(),
  `American Indian/Alaska Native students share` = col_character(),
  `Asian or Asian/Pacific Islander students share` = col_character(),
  `Hispanic students share` = col_character(),
  `Black students share` = col_character(),
  `White students share` = col_character(),
  `Hawaiian Nat./Pacific Isl. students share` = col_character(),
  `Two or more races students share` = col_character()
) -> esos_cols

esos_url <- "https://files.osf.io/v1/resources/zeqrj/providers/osfstorage/606d08c651f7ae0239f50caf?action=download&direct&version=1"

esos <- read_csv(esos_url, col_types = esos_cols)
esos <- clean_names(esos) # sane column names

# this doesn't get converted b/c it's a mix of numbers and some text 
# making it numeric in the schema would generate warnings so better to
# do that here as there will be NAs but now you know that's "a thing" 
# vs guess as to whether it was just a data xfer issue
esos$total_elementary_students <- as.numeric(esos$total_elementary_students)

# "fix" the nces_district_id column since it forgets to put leading `0` in states with numeric FIPS < 10
esos$nces_district_id[nchar(esos$nces_district_id) == 6] <- sprintf("0%s", esos$nces_district_id[nchar(esos$nces_district_id) == 6])

# pick some fields for the map 
esos$in_person <- as.logical(esos$in_person)
esos$fully_remote <- as.logical(esos$fully_remote)
esos$hybrid_part_day <- as.logical(esos$hybrid_part_day)
esos$hybrid_part_week <- as.logical(esos$hybrid_part_week)
esos$hybrid_rotating_weeks <- as.logical(esos$hybrid_rotating_weeks)
esos$hybrid_other <- as.logical(esos$hybrid_other)

# focus on the lower 48 b/c "easy"
edge_c %>% 
  filter(
    !(postal_code %in% c("HI", "PR", "AK", "VI", "MP", "AS", "GU", "HI", "PR")),
    !is.na(postal_code)
  ) %>% 
  left_join(
    esos %>% 
      select(
        nces_district_id, in_person, fully_remote, hybrid_part_day, hybrid_part_week, 
        hybrid_rotating_weeks, hybrid_other, total_elementary_students
      ) %>% 
      gather(measure, value, -nces_district_id, -total_elementary_students) %>% 
      filter(value) %>% 
      mutate(
        measure = stri_replace_all_fixed(measure, "_", " ") %>% # make nice facet labels
          stri_trans_totitle() %>% 
          factor(
            levels = c(
              "In Person", "Fully Remote", "Hybrid Part Week", 
              "Hybrid Rotating Weeks", "Hybrid Part Day", "Hybrid Other"
            )
          )
      ),
    by = c("GEOID" = "nces_district_id")
  ) %>% 
  filter(!is.na(measure)) -> lower_48

usa <- st_read("states-albers-composite.geojson")

ggplot() +
  geom_sf(
    data = usa %>% filter(!(name %in% c("Alaska", "Hawaii"))), # just lower 48
    size = 0.100, color = "#FFFFFF22"
  ) +
  geom_sf(
    data = lower_48,
    aes(size = total_elementary_students, group = measure, fill = measure),
    shape = 21, color = "white", stroke = 0.125, alpha = 3/4
  ) +
  scale_size_area(
    breaks = c(100, 500, 1000, 2500, 5000, 10000, 50000, 100000, 200000, 400000, 500000),
    limits = range(esos$total_elementary_students, na.rm = TRUE),
    label = scales::comma_format(1)
  ) +
  coord_sf(crs = albersusa::us_laea_proj, datum = NA) +
  facet_wrap(~measure) +
  guides(
    size = guide_legend(override.aes = list(alpha = 1, color = "white")),
    fill = guide_none()
  ) +
  labs(
    x = NULL, y = NULL, size = "Total Students", fill = NA,
    title = "Elementary School Operating Status (Continental US)",
    caption = "Paper & Data Source: https://osf.io/zeqrj/ • DOI 10.17605/OSF.IO/ZEQRJ"
  ) +
  theme_inter(grid="", mode = "dark") +
  theme(
    axis.text.x.bottom = element_blank(),
    axis.text.y.left = element_blank()
  )
