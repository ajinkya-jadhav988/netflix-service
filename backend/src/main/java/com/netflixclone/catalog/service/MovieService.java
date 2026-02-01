package com.netflixclone.catalog.service;

import com.netflixclone.catalog.model.Movie;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class MovieService {

    private final List<Movie> movies = List.of(
        new Movie(
            1L,
            "Breaking Bad",
            "Drama",
            "/images/Breaking_Bad_title_card.png"
        ),
        new Movie(
            2L,
            "Money Heist",
            "Thriller",
            "/images/MoneyHeist-Korea-logo.png"
        ),
        new Movie(
            3L,
            "Stranger Things",
            "Sci-Fi",
            "/images/wp11155493.jpg"
        )
    );

    public List<Movie> getAllMovies() {
        return movies;
    }

    public Movie getMovieById(Long id) {
        return movies.stream()
                .filter(movie -> movie.getId().equals(id))
                .findFirst()
                .orElse(null);
    }
}

