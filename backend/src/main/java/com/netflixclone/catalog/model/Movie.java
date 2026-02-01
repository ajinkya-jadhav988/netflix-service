package com.netflixclone.catalog.model;

public class Movie {

    private Long id;
    private String title;
    private String genre;
    private String imageUrl;

    public Movie(Long id, String title, String genre, String imageUrl) {
        this.id = id;
        this.title = title;
        this.genre = genre;
        this.imageUrl = imageUrl;
    }

    public Long getId() {
        return id;
    }

    public String getTitle() {
        return title;
    }

    public String getGenre() {
        return genre;
    }

    public String getImageUrl() {
        return imageUrl;
    }
}

