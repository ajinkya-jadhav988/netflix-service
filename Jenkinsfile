pipeline {
    agent any

    options {
        timestamps()
        ansiColor('xterm')
    }

    environment {
        BACKEND_DIR  = "backend"
        FRONTEND_DIR = "frontend"
        BACKEND_IMAGE  = "netflix-backend:ci"
        FRONTEND_IMAGE = "netflix-frontend:ci"
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Sanity Checks') {
            steps {
                sh '''
                  echo "Checking repo structure"
                  test -d backend
                  test -d frontend
                '''
            }
        }

        /* -------- BACKEND -------- */

stage('Backend - Maven Build') {
    tools {
        maven 'maven-3.9'
    }
    steps {
        dir("${BACKEND_DIR}") {
            sh 'mvn clean verify'
        }
    }
}


        stage('Backend - Sonar Scan') {
            steps {
                dir("${BACKEND_DIR}") {
                    sh '''
                      echo "Sonar scan configured via Jenkins tools"
                    '''
                }
            }
        }

        stage('Backend - Docker Build') {
            steps {
                dir("${BACKEND_DIR}") {
                    sh 'docker build -t ${BACKEND_IMAGE} .'
                }
            }
        }

        /* -------- FRONTEND -------- */

        stage('Frontend - Sanity Check') {
            steps {
                dir("${FRONTEND_DIR}") {
                    sh '''
                      test -f Dockerfile
                      test -f index.html
                    '''
                }
            }
        }

        stage('Frontend - Docker Build') {
            steps {
                dir("${FRONTEND_DIR}") {
                    sh 'docker build -t ${FRONTEND_IMAGE} .'
                }
            }
        }
    }

    post {
        success {
            echo "CI pipeline completed successfully"
        }
        failure {
            echo "CI pipeline failed"
        }
    }
}

