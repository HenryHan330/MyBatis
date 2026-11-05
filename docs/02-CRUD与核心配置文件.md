# 02 CRUD 与核心配置文件

> 本篇目标：把「增删改查」写熟，并彻底看懂 `mybatis-config.xml`。
> 表：`t_car(id, car_num, brand, guide_price, produce_time, car_type)`

## 1. insert

### 1.1 用 Map 传值（入门最直观）

```xml
<insert id="insertCarByMap" parameterType="map">
    insert into t_car(id, car_num, brand, guide_price, produce_time, car_type)
    values(null, #{carNum}, #{brand}, #{guidePrice}, #{produceTime}, #{carType})
</insert>
```

```java
Map<String, Object> map = new HashMap<>();
map.put("carNum", "1001");
map.put("brand", "宝马520Li");
map.put("guidePrice", 10.0);
map.put("produceTime", "2020-10-11");
map.put("carType", "燃油车");

SqlSession sqlSession = SqlSessionUtil.openSession();
int count = sqlSession.insert("insertCarByMap", map);
sqlSession.commit();
SqlSessionUtil.closeSqlSession();
```

**要点**

- `#{carNum}` 里写的是 **map 的 key**，不是列名。
- key 写错了**不会报错**，只会插入 `NULL` —— 这是最阴的坑，一定要开 `STDOUT_LOGGING` 看 `Parameters`。

### 1.2 用 POJO 传值（推荐）

```xml
<insert id="insertCarByPOJO">
    insert into t_car(id, car_num, brand, guide_price, produce_time, car_type)
    values(null, #{carNum}, #{brand}, #{guidePrice}, #{produceTime}, #{carType})
</insert>
```

```java
Car car = new Car(null, "1002", "宝马540Li", 30.0, "2021-11-11", "新能源");
sqlSession.insert("insertCarByPOJO", car);
```

- `#{}` 里写的是 **Java 对象的属性名**（不含 `get`，首字母小写）。
- MyBatis 通过 **getter** 取值：写 `carNum` 实际调用 `getCarNum()`；**所以属性必须提供 getter**。

### 1.3 `parameterType` 属性

| 写法 | 说明 |
| --- | --- |
| 不写 | **推荐**。MyBatis 能通过方法参数自动推断类型 |
| `parameterType="java.util.Map"` | 或别名 `map` |
| `parameterType="com.jkweilai.mybatis.pojo.Car"` | 或配置了别名后用 `Car` |

> `parameterType` 只影响可读性，写错了一般也不影响执行（能被推断出来），属于「可以省略」的属性。

### 1.4 插入时获取自动生成的主键

```xml
<insert id="insertCarReturnKey" useGeneratedKeys="true" keyProperty="id">
    insert into t_car values(null, #{carNum}, #{brand}, #{guidePrice}, #{produceTime}, #{carType})
</insert>
```

- `useGeneratedKeys="true"`：使用数据库的自增主键
- `keyProperty="id"`：把生成的主键回填到对象的 `id` 属性上
- 执行后 `car.getId()` 就有值了（常用于「主表插入后拿 id 插从表」）

## 2. delete

```xml
<delete id="deleteById">
    delete from t_car where id = #{id}
</delete>
```

```java
int count = sqlSession.delete("deleteById", 5L);
```

- **单参数**时 `#{}` 里写什么都可以（`#{id}`、`#{abc}`、`#{value}` 都行），因为只有一个 `?`。
- 返回的是**影响行数**，删除 0 条不报错。

## 3. update

> ⚠️ **`where` 一定要写！** 漏写 `where` 会更新整张表，练习时务必先 `select` 确认条件。

```xml
<update id="updateCarById">
    update t_car set
        car_num = #{carNum},
        brand = #{brand},
        guide_price = #{guidePrice},
        produce_time = #{produceTime},
        car_type = #{carType}
    where id = #{id}
</update>
```

## 4. select

### 4.1 查一条

```xml
<select id="selectById" resultType="com.jkweilai.mybatis.pojo.Car">
    select * from t_car where id = #{id}
</select>
```

```java
Car car = sqlSession.selectOne("selectById", 1L);
```

- `resultType`：查询结果**每一条**要封装成什么类型（不是 `List`）。
- 结果超过 1 条会抛 `TooManyResultsException`。

### 4.2 查多条

```xml
<select id="selectAll" resultType="Car">
    select * from t_car
</select>
```

```java
List<Car> cars = sqlSession.selectList("selectAll");
```

**前提**：列名和属性名对得上（`car_num` ↔ `carNum` 需要驼峰映射或 `resultMap`，详见 [04 篇](04-查询与结果映射.md)）。

## 5. namespace 到底有什么用

- `namespace` + `id` 组成 **MappedStatement 的唯一标识**（`namespace.id`）。
- 同一个 `namespace` 下的 `id` 不能重复；不同 namespace 可以重复。
- **规范写法（后面接口代理要用）**：`namespace` = 接口的**全限定名**，`id` = 方法名。

```xml
<mapper namespace="com.jkweilai.mybatis.mapper.CarMapper">
    <select id="selectById" resultType="Car">...</select>
</mapper>
```

调用时：

```java
sqlSession.selectOne("com.jkweilai.mybatis.mapper.CarMapper.selectById", 1L);
```

**典型异常**

```text
org.apache.ibatis.exceptions.PersistenceException:
### Error querying database.
### Cause: java.lang.IllegalArgumentException: Mapped Statements collection does not contain value for xxx
```

⇒ namespace/id 没对上，或 XML 没被 `mappers` 加载。

## 6. 核心配置文件详解

`mybatis-config.xml` 是 MyBatis 的全局配置，标签顺序不可乱。下面按使用频率讲。

### 6.1 `environments`：多环境

```xml
<environments default="development">
    <environment id="development">
        <transactionManager type="JDBC"/>
        <dataSource type="POOLED">...</dataSource>
    </environment>
    <environment id="test">
        <transactionManager type="JDBC"/>
        <dataSource type="UNPOOLED">...</dataSource>
    </environment>
</environments>
```

- `default` 指定默认使用哪个环境。
- 一个 `environment` = 一个 **数据源 + 事务管理器** 的组合。
- MyBatis 原生项目里切换环境要改 XML；Spring Boot 下不需要这套，直接 `application.yml`。

### 6.2 `transactionManager`：只有两个可选值

| 值 | 实现类 | 说明 |
| --- | --- | --- |
| `JDBC` | `JdbcTransactionFactory` | 依赖数据源拿到的连接来控制事务，`commit()/rollback()` 底层是 `conn.commit()/rollback()`，和 JDBC 一样 |
| `MANAGED` | `ManagedTransactionFactory` | 事务交给**容器**（Tomcat、Spring）管理，自己调 `commit()` 没效果 |

> 单独用 MyBatis（没有 Spring）时选 `JDBC`，这也是绝大多数示例的写法。

### 6.3 `dataSource`：三种类型

| type | 说明 | 适用 |
| --- | --- | --- |
| `UNPOOLED` | 每次请求都 **新建连接、用完直接关闭**，没有池化 | 学习、低并发 |
| `POOLED` | 维护一个连接池，**用完归还**而不是关闭（`PooledDataSource`） | **默认、最常用** |
| `JNDI` | 从容器（Tomcat/WebLogic）的 JNDI 上下文里找数据源 | 企业级容器管理数据源 |

**实测对比**（笔记里做过）：把 `type` 从 `POOLED` 改成 `UNPOOLED`，循环插入 100 条，耗时会明显上升 —— 因为每次插入都要 TCP 三次握手 + MySQL 认证。

`POOLED` 可配的连接池参数（放在 `<dataSource>` 里作为 `<property>`）：

| 属性 | 默认值 | 含义 |
| --- | --- | --- |
| `poolMaximumActiveConnections` | 10 | 最大活跃连接数 |
| `poolMaximumIdleConnections` | 5 | 最大空闲连接数 |
| `poolMaximumCheckoutTime` | 20000（ms） | 连接被借出的最长时间，超时强制回收 |
| `poolTimeToWait` | 20000（ms） | 池里没连接时，等待多久后打印日志并重试 |
| `poolPingEnabled` | false | 是否开启连接探活（防止 MySQL 8 小时断连） |
| `poolPingQuery` | `NO PING QUERY SET` | 探活 SQL，一般设 `select 1` |
| `poolPingConnectionsNotUsedFor` | 0 | 多久没用的连接才需要探活（配合 `poolPingEnabled`） |

### 6.4 `properties`：外部化数据库配置

**方式一：外部文件（推荐）**

`src/main/resources/jdbc.properties`

```properties
jdbc.driver=com.mysql.cj.jdbc.Driver
jdbc.url=jdbc:mysql://localhost:3306/mybatis
jdbc.username=root
jdbc.password=root
```

```xml
<properties resource="jdbc.properties"/>

<dataSource type="POOLED">
    <property name="driver" value="${jdbc.driver}"/>
    <property name="url" value="${jdbc.url}"/>
    <property name="username" value="${jdbc.username}"/>
    <property name="password" value="${jdbc.password}"/>
</dataSource>
```

**方式二：直接写在 XML 里**

```xml
<properties>
    <property name="jdbc.username" value="root"/>
    <property name="jdbc.password" value="root"/>
</properties>
```

**优先级（从高到低）**

1. `SqlSessionFactoryBuilder.build(in, props)` 以方法参数传入的 `Properties`
2. `properties` 元素的 `resource` / `url` 指向的外部文件
3. `properties` 元素内部 `property` 子标签

### 6.5 `mappers`：四种注册方式

```xml
<mappers>
    <!-- 1. resource：类路径下，最常见 -->
    <mapper resource="com/jkweilai/mybatis/mapper/CarMapper.xml"/>
    <!-- 2. url：绝对路径 / 网络路径，不推荐（部署到服务器就失效） -->
    <mapper url="file:///D:/mapper/CarMapper.xml"/>
    <!-- 3. class：接口全限定名，要求 XML 与接口同包同名 -->
    <mapper class="com.jkweilai.mybatis.mapper.CarMapper"/>
    <!-- 4. package：批量注册包下所有接口，最省事 -->
    <package name="com.jkweilai.mybatis.mapper"/>
</mappers>
```

> **`class` / `package` 的隐藏要求**：XML 必须和接口**同包同名**（`CarMapper.java` 与 `CarMapper.xml` 放在同一个 package 下）。
> 而 Maven 默认**不会**把 `src/main/java` 下的 `*.xml` 复制到 `target/classes`，所以要么把 XML 放 `resources`（保持同样的包路径），要么在 `pom.xml` 加：

```xml
<build>
    <resources>
        <resource>
            <directory>src/main/java</directory>
            <includes>
                <include>**/*.xml</include>
            </includes>
        </resource>
        <resource>
            <directory>src/main/resources</directory>
        </resource>
    </resources>
</build>
```

**这是新手 90% 的「Invalid bound statement」根因。**

