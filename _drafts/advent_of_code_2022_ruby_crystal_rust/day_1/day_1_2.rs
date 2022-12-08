use std::fs;

fn parse_and_search_calories(filename: &str) -> Vec<i32> {
    let text = fs::read_to_string(filename).unwrap();

    let mut numbers: Vec<i32> = text
        .split("\n\n")
        .map(|group| {
            group
                .trim()
                .split("\n")
                .map(|line| line.parse::<i32>().unwrap())
                .sum()
        })
        .collect::<Vec<_>>();

    numbers.sort_by(|a, b| b.cmp(a));
    numbers.truncate(3);
    numbers
}

fn main() {
    let top_calories = parse_and_search_calories("input.txt");
    let sum_calories = top_calories.iter().sum::<i32>();
    print!("{:?}\n{}\n", top_calories, sum_calories);
}
