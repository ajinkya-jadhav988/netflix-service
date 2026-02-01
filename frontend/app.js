const API_URL = "http://65.2.3.52:8080/movies"; 
// ⚠️ Use your EC2 PUBLIC IP (not localhost)

fetch(API_URL)
  .then(response => response.json())
  .then(data => {
    const moviesDiv = document.getElementById("movies");
    moviesDiv.innerHTML = ""; // clear existing content

    data.forEach(movie => {
      const card = document.createElement("div");
      card.className = "movie-card";

      card.innerHTML = `
        <img src="${movie.imageUrl}" alt="${movie.title}" class="movie-img" />
        <div class="movie-title">${movie.title}</div>
        <div class="movie-genre">${movie.genre}</div>
      `;

      moviesDiv.appendChild(card);
    });
  })
  .catch(err => {
    console.error("Error fetching movies:", err);
  });

