### Requirements

- [Java](https://www.java.com/)
- [Maven](https://maven.apache.org/)
- [Gradle](https://gradle.org/)
- [Spring-boot-cli](https://spring.io/projects/spring-boot)

### Description

A folk of [pojokcodeid/auto-java-project.nvim](https://github.com/pojokcodeid/auto-java-project.nvim)

### Installation

```lua
-- lua with lazy.nvim
return {
    "nhattVim/java-project.nvim",
    opts = {},
    cmd = {
        "NewMavenProject",
        "NewGradleProject",
        "NewSpringBootProject",
    },
}
```
