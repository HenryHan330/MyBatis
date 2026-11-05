# MyBatis & MyBatis-Plus 个人学习笔记

> 本仓库是我的 **MyBatis / MyBatis-Plus 个人笔记 + 代码骨架**。
> 内容整理自《MyBatis概述》文档（语雀导出 docx），按「**重点章节写全、次要章节一笔带过**」重新组织，并修正了原文里的路径错误、包名不统一、HTML 残留等问题。
>
> 约定：示例包名统一为 `com.jkweilai.mybatis` 与 `com.jkweilai.mp`，注释风格沿用教程原文（`@author 老杜`）。

---

## 一、笔记索引

### 第一部分：MyBatis（手写 SQL，吃透原理）

| 编号 | 笔记 | 核心内容 | 重要度 |
| --- | --- | --- | --- |
| 01 | [概述与入门程序](docs/01-概述与入门程序.md) | 三层架构、JDBC 的痛点、ORM、第一个程序六步走、`SqlSessionUtil`、`STDOUT_LOGGING` | ★★★★★ |
| 02 | [CRUD 与核心配置文件](docs/02-CRUD与核心配置文件.md) | insert/delete/update/select、Map 与 POJO 传值、`parameterType`、`environments`、三种 `dataSource`、`properties`、`mappers` | ★★★★★ |
| 03 | [接口代理与参数处理](docs/03-接口代理与参数处理.md) | `getMapper` 代理机制、`#{}` vs `${}`、五种传参方式、`@Param`、`typeAliases`、主键回填 | ★★★★★ |
| 04 | [查询与结果映射](docs/04-查询与结果映射.md) | 返回 Car/List/Map/List&lt;Map&gt;/Map&lt;String,Map&gt;、`resultMap`、驼峰自动映射、count | ★★★★☆ |
| 05 | [动态 SQL](docs/05-动态SQL.md) | `if`、`where`、`trim`、`set`、`choose`、`foreach`、`sql`/`include` | ★★★★★ |
| 06 | [高级映射与延迟加载](docs/06-高级映射与延迟加载.md) | 多对一（级联/association/分步）、一对多（collection/分步）、`fetchType`、`lazyLoadingEnabled` | ★★★★☆ |
| 07 | [缓存、逆向工程、PageHelper、注解](docs/07-缓存与逆向工程与PageHelper与注解.md) | 一级/二级缓存、MBG 逆向工程、分页插件、注解式开发 | ★★★☆☆ |
| 08 | [Web 三层架构与事务](docs/08-Web三层架构与事务.md) | 转账案例、对象作用域、`ThreadLocal` 保证同一 `SqlSession` | ★★★★☆ |

### 第二部分：MyBatis-Plus（单表 CRUD 零 SQL）

| 编号 | 笔记 | 核心内容 | 重要度 |
| --- | --- | --- | --- |
| 09 | [MP 入门、注解与配置](docs/09-MP-入门注解与配置.md) | `BaseMapper`、`@TableName/@TableId/@TableField`、yaml 配置、主键策略、逻辑删除入门 | ★★★★★ |
| 10 | [条件构造器与 IService](docs/10-MP-条件构造器与IService.md) | `QueryWrapper`/`UpdateWrapper`/`LambdaQueryWrapper`、`IService` 常用方法、`lambdaQuery()`/`lambdaUpdate()`、批量新增、自定义 SQL | ★★★★★ |
| 11 | [MP 进阶特性](docs/11-MP-进阶特性.md) | 分页插件、逻辑删除、枚举处理器、JSON 处理器、`Db` 静态工具类、代码生成器 | ★★★★☆ |

### 附录

- [docs/sql/init.sql](docs/sql/init.sql)：全部示例表 DDL + 初始化数据（`t_car`、`t_act`、`t_clazz`、`t_student` 等）

---

## 二、学习路线

```text
01 概述与入门 ──► 02 CRUD + 核心配置 ──► 03 接口代理 + 参数处理
        │                                        │
        └──► 08 Web 三层架构 + 事务               ├──► 04 查询与结果映射
                                                 └──► 05 动态 SQL
                                                          │
                                       06 高级映射 + 延迟加载 ──► 07 缓存 / 逆向工程 / PageHelper / 注解
                                                          │
                                                          ▼
                                              09 MP 入门 ──► 10 条件构造器 + IService ──► 11 MP 进阶
```

> 一句话区分两个框架：**MyBatis 你要手写 SQL，灵活但要写**；**MyBatis-Plus 只做增强不做改变，单表 CRUD 一行不写**。多表复杂查询、需要精细调优的 SQL，仍然回到 MyBatis 的 XML。

---

## 三、环境准备

| 组件 | 版本（笔记所用） | 备注 |
| --- | --- | --- |
| JDK | 8 / 17 | MP + Spring Boot 3 要求 **JDK 17+** |
| MySQL | 8.x | 库名 `mybatis`，字符集 `utf8mb4` |
| MyBatis | 3.5.19 | 3.5.2+ 已修复单个简单参数在 OGNL 中的取值问题 |
| MySQL 驱动 | `mysql-connector-java:8.0.24` | Spring Boot 项目改用 `com.mysql:mysql-connector-j`（版本由父工程管） |
| JUnit | 5.10.2 | `junit-jupiter` |
| MyBatis-Plus | 3.5.11 | Spring Boot 3 用 `mybatis-plus-spring-boot3-starter` |
| 分页插件 | `mybatis-plus-jsqlparser:3.5.11` | 3.5.9+ 分页插件被拆到这个包 |
| Tomcat | 10+ | **`jakarta.servlet.*`**；若用 Tomcat 9 则仍为 `javax.servlet.*` |

初始化数据库：

```sql
CREATE DATABASE IF NOT EXISTS `mybatis` DEFAULT CHARACTER SET utf8mb4;
-- 建表脚本见 docs/sql/init.sql
```

---

## 四、踩坑速查（笔记中标记为「坑」的地方）

1. **`javax.servlet` vs `jakarta.servlet`**：原文 pom 引的是 `jakarta.servlet-api:6.0.0`（Tomcat 10+），但 `AccountController` 里 `import javax.servlet.*`，两者不匹配会报「找不到符号」。要么统一用 `jakarta.servlet.*` + Tomcat 10+，要么退回 Tomcat 9 + `javax.servlet-api:4.0.1`。
2. **XML 放在 `src/main/java` 下不会被打包**：`mapper resource="..."` 只从类路径（`target/classes`）找，必须放 `resources`，或者在 `pom.xml` 里配 `<resources>` 把 java 目录下的 `**/*.xml` 也复制过去。
3. **`#{}` 里写错 key 不报错**：Map 传值时 key 不存在只会插入 `NULL`，非常隐蔽。
4. **单参数 `#{}` 内容可随便写**：因为只有一个占位符，MyBatis 不做名字匹配；但 `@Param` / `_parameter` 在动态 SQL 的 `test` 里仍需注意（3.5.1 及以前会报错）。
5. **`resultType` 忘了写**：报 `A query was run and no Result Maps were found`。
6. **列名与属性名不一致**：只赋值 `id`、`brand` 这种恰好同名的字段，其余为 `null`；用 `as` 别名 / `resultMap` / 驼峰映射解决。
7. **service 与 dao 各自 `openSession()` 导致事务失效**：必须用 `ThreadLocal` 让同一线程共用同一个 `SqlSession`。
8. **`SqlSession` 非线程安全**：不能做成员变量、不能放 `HttpSession`，用「方法作用域 + `finally` 关闭」。
9. **二级缓存必须在 `SqlSession.close()/commit()` 之后才可命中**。
10. **MP 分页插件 3.5.9+ 需单独引入 `mybatis-plus-jsqlparser`**，否则分页不生效（SQL 不拼 `LIMIT`）。
