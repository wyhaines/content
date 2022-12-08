use std::fs;

fn parse_and_search_calories(filename: &str) -> i32 {
    let text = fs::read_to_string(filename).unwrap();

    text.split("\n\n")
        .map(|group| {
            group
                .trim()
                .split("\n")
                .map(|line| line.parse::<i32>().unwrap())
        })
        .map(|numbers| numbers.sum())
        .max().unwrap()
}

fn main() {
    print!("{}\n", parse_and_search_calories("input.txt"));
}
